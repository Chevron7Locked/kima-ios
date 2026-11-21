import Foundation

/// Where a FLAC stream should start so that it plays from a given moment: the byte of the frame
/// holding (or just before) that moment, and the sample that frame starts at. Found with small
/// range requests: the header's seek table narrows it, then a bisection over frame headers.
struct FLACStart: Equatable {
    let byte: Int
    let sample: Int
}

/// What the finder needs from a stream: bytes by range, and the stream's full length.
struct FLACByteSource {
    /// `range` is a byte range of the file; returns those bytes (possibly fewer at the end) and
    /// the file's total length.
    let read: (Range<Int>) async throws -> (data: Data, total: Int)

    /// The server answered without honouring the range: it can't serve a stream from mid-track.
    struct NoRanges: Error {}

    /// Over HTTP with a `Range` header, the way the hub serves a stream, on a session from the
    /// session factory. A reply that isn't a range (a 200 is the whole file) is dropped unread and
    /// throws `NoRanges`.
    static func http(_ url: URL, session: URLSession) -> FLACByteSource {
        FLACByteSource { range in
            var request = URLRequest(url: url)
            request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 206 else {
                bytes.task.cancel()
                if (response as? HTTPURLResponse)?.statusCode == 200 { throw NoRanges() }
                throw URLError(.badServerResponse)
            }
            let header = http.value(forHTTPHeaderField: "Content-Range") ?? ""
            guard let total = header.split(separator: "/").last.flatMap({ Int($0) }) else {
                bytes.task.cancel()
                throw URLError(.badServerResponse)
            }
            var data = Data(capacity: range.count)
            for try await byte in bytes { data.append(byte) }
            return (data, total)
        }
    }
}

/// A FLAC stream's layout plus its length: everything needed to build a stream that starts mid-track.
struct FLACStream: Equatable {
    /// Bytes asked for per header read: STREAMINFO and a typical SEEKTABLE fit in the first.
    static let headerWindow = 16_384

    let layout: FLACLayout
    let fileLength: Int

    /// Reads the metadata blocks (skipping the bytes of any it doesn't need, like cover art).
    /// Nil when the stream isn't a FLAC this can start mid-track (another format, no sample count, or a
    /// server without ranges).
    static func read(from source: FLACByteSource) async throws -> FLACStream? {
        let first: (data: Data, total: Int)
        do { first = try await source.read(0..<Self.headerWindow) } catch is FLACByteSource.NoRanges { return nil }
        let total = first.total
        // `b` holds file bytes from 0 up to what's been read, except a skipped block's body
        // (cover art can be megabytes), whose place is kept with zeros only if read past.
        var b = [UInt8](first.data)
        guard b.count >= 42, Array(b[0..<4]) == Array("fLaC".utf8) else { return nil }
        var streamInfo: [UInt8]?
        var seekPoints: [FLACLayout.SeekPoint] = []
        var at = 4
        func readOn(to end: Int) async throws {
            guard end > b.count, b.count < total else { return }
            let from = b.count
            let more = try await source.read(from..<end)
            b += more.data
        }
        while true {
            if at + 4 > b.count {   // a block header past what was read: jump to it
                let more = try await source.read(at..<at + Self.headerWindow)
                b = Array(b.prefix(at)) + [UInt8](repeating: 0, count: max(0, at - b.count)) + more.data
            }
            guard at + 4 <= b.count else { return nil }
            let isLast = b[at] & 0x80 != 0, type = b[at] & 0x7F
            let length = b[at + 1...at + 3].bigEndian
            let body = at + 4
            if type == 0 || type == 3 {   // STREAMINFO, SEEKTABLE: need the body
                try await readOn(to: body + length + 4)
                guard body + length <= b.count else { return nil }
                let block = Array(b[body..<body + length])
                if type == 0 { streamInfo = block } else { seekPoints = Self.seekPoints(block) }
            }
            at = body + length
            if isLast { break }
        }
        guard let streamInfo, streamInfo.count == 34 else { return nil }
        let layout = FLACLayout(streamInfo: streamInfo, audioStart: at, seekPoints: seekPoints)
        guard layout.totalSamples > 0, layout.sampleRate > 0 else { return nil }
        return FLACStream(layout: layout, fileLength: total)
    }

    private static func seekPoints(_ block: [UInt8]) -> [FLACLayout.SeekPoint] {
        stride(from: 0, to: block.count - 17, by: 18).compactMap { i in
            guard !block[i..<i + 8].allSatisfy({ $0 == 0xFF }) else { return nil }   // placeholder point
            return FLACLayout.SeekPoint(sample: block[i..<i + 8].bigEndian, offset: block[i + 8..<i + 16].bigEndian)
        }
    }

    // MARK: - Finding the start

    /// The frame to start from to hear `seconds`: the last frame starting at or before it, or one
    /// a fraction of a second earlier (close enough that the shown time stays honest, since the
    /// clock is set from the frame's own sample number).
    func start(at seconds: Double, from source: FLACByteSource) async throws -> FLACStart? {
        let rate = layout.sampleRate
        let target = min(max(0, Int(seconds * Double(rate))), layout.totalSamples - 1)
        let close = rate / 4
        // Bounds from the seek table: lo at or before the target, hi after it.
        var lo = FLACStart(byte: layout.audioStart, sample: 0)
        var hi = FLACStart(byte: fileLength, sample: layout.totalSamples)
        for point in layout.seekPoints {
            let start = FLACStart(byte: layout.audioStart + point.offset, sample: point.sample)
            if point.sample <= target, point.sample >= lo.sample { lo = start }
            if point.sample > target, point.sample < hi.sample { hi = start }
        }
        var window = max(layout.maxFrameSize > 0 ? layout.maxFrameSize * 2 : 0, 32_768)

        var reads = 0
        while target - lo.sample > close, reads < 24 {
            reads += 1
            // Read where the target falls by bytes-per-sample between the bounds; a frame header
            // found there tightens one bound. Near the end, read everything left between them.
            let span = hi.byte - lo.byte
            let readsAll = span <= window * 2   // what's left between the bounds fits one read
            let from: Int
            if readsAll {
                from = lo.byte
            } else {
                let fraction = Double(target - lo.sample) / Double(max(1, hi.sample - lo.sample))
                from = min(max(lo.byte + 1, lo.byte + Int(Double(span) * fraction) - window / 2), hi.byte - window)
            }
            let end = min(hi.byte, from + (readsAll ? span : window))
            let data = try await source.read(from..<end).data
            let frames = layout.frames(in: [UInt8](data), base: from, samples: lo.sample...hi.sample)
                .filter { $0.byte > lo.byte || $0.sample == lo.sample }
            guard !frames.isEmpty else {
                if readsAll { break }   // nothing between the bounds: lo is the frame
                window *= 2   // frames bigger than the header said: read wider
                continue
            }
            if let before = frames.last(where: { $0.sample <= target }) { lo = FLACStart(byte: before.byte, sample: before.sample) }
            if let after = frames.first(where: { $0.sample > target }) { hi = FLACStart(byte: after.byte, sample: after.sample) }
            if readsAll { break }
        }
        return lo
    }
}
