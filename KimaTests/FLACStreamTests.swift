import XCTest
@testable import Kima

/// Finding where a FLAC stream must start to play from a given moment, from the file's own bytes.
/// Real libraries carry cover art in the header, and not every encoder writes a seek table.
final class FLACStreamTests: XCTestCase {
    private var flac: Data!

    override func setUpWithError() throws {
        flac = try FLACClockFixture.data()
    }

    /// Reads from memory, counting the reads.
    private final class Counter { var reads = 0 }
    private func memory(_ data: Data, counter: Counter = Counter()) -> FLACByteSource {
        FLACByteSource { range in
            counter.reads += 1
            let r = min(range.lowerBound, data.count)..<min(range.upperBound, data.count)
            return (data.subdata(in: r), data.count)
        }
    }

    private func assertFinds(in data: Data, file: StaticString = #filePath, line: UInt = #line) async throws {
        let source = memory(data)
        let read = try await FLACStream.read(from: source)
        let stream = try XCTUnwrap(read, file: file, line: line)
        for target in [0.0, 12.5, 45.0, 80.0, 89.9] {
            let found = try await stream.start(at: target, from: source)
            let start = try XCTUnwrap(found, file: file, line: line)
            let at = Double(start.sample) / FLACClockFixture.sampleRate
            XCTAssertLessThanOrEqual(at, target + 0.0001, "start for \(target)", file: file, line: line)
            XCTAssertGreaterThan(at, target - 0.25, "start for \(target)", file: file, line: line)
            // The byte really is a frame header for that sample.
            let frame = [UInt8](data[start.byte..<min(data.count, start.byte + 32)])
            XCTAssertEqual(stream.layout.frameSample(in: frame, at: 0), start.sample, file: file, line: line)
        }
    }

    /// The metadata blocks: (offset of block header, type).
    private func blocks(_ data: Data) -> [(at: Int, type: UInt8)] {
        var out: [(Int, UInt8)] = [], at = 4
        while true {
            let type = data[at] & 0x7F, last = data[at] & 0x80 != 0
            out.append((at, type))
            at += 4 + (Int(data[at + 1]) << 16 | Int(data[at + 2]) << 8 | Int(data[at + 3]))
            if last { return out }
        }
    }

    // MARK: - Header

    func testTheHeaderCountsOnlyTheSamplesLeftAndForgetsTheChecksum() {
        var info = [UInt8](repeating: 0, count: 34)
        info[2] = 0x10; info[3] = 0x00                  // max block 4096
        info[10] = 0x05; info[11] = 0x62; info[12] = 0x23  // 22050 Hz (20 bits), 2 channels (3), bits' top bit
        info[13] = 0x70                                 // bits - 1 = 0b10111 → 24; sample count's top nibble 0
        info[16] = 0x03; info[17] = 0xE8                // 1000 samples
        for k in 18..<34 { info[k] = 0xAB }             // an MD5
        let layout = FLACLayout(streamInfo: info, audioStart: 42, seekPoints: [])
        XCTAssertEqual(layout.sampleRate, 22_050)
        XCTAssertEqual(layout.bitsPerSample, 24)
        XCTAssertEqual(layout.totalSamples, 1000)

        let header = [UInt8](layout.header(startingAt: 400))
        XCTAssertEqual(header.count, 42)
        XCTAssertEqual(Array(header[0..<8]), [0x66, 0x4C, 0x61, 0x43, 0x80, 0x00, 0x00, 0x22])   // fLaC, last STREAMINFO, 34
        XCTAssertEqual(Array(header[8 + 13..<8 + 18]), [0x70, 0x00, 0x00, 0x02, 0x58])           // 600 left
        XCTAssertEqual(Array(header[8 + 18..<42]), [UInt8](repeating: 0, count: 16))
    }

    // MARK: - Frames

    func testAFrameHeaderWithABadChecksumIsNotAFrame() async throws {
        let read = try await FLACStream.read(from: memory(flac))
        let stream = try XCTUnwrap(read)
        let start = stream.layout.audioStart
        var bytes = [UInt8](flac[start..<start + 32])
        XCTAssertEqual(stream.layout.frameSample(in: bytes, at: 0), 0)
        // Frame number 0 → 1 is still a well-formed header; only the CRC-8 can tell it's wrong.
        bytes[4] = 0x01
        XCTAssertNil(stream.layout.frameSample(in: bytes, at: 0))
    }

    // MARK: - Finding

    /// Apple's encoder writes no seek table: the fixture as written is that case.
    func testFindsTheFrameWithoutASeekTable() async throws {
        let read = try await FLACStream.read(from: memory(flac))
        XCTAssertEqual(try XCTUnwrap(read).layout.seekPoints, [])
        XCTAssertFalse(blocks(flac).contains { $0.type == 3 })
        try await assertFinds(in: flac)
    }

    /// Most encoders (flac, ffmpeg) write one: a point every 10 s, as `flac` does by default.
    func testFindsTheFrameWithASeekTable() async throws {
        let read = try await FLACStream.read(from: memory(flac))
        let layout = try XCTUnwrap(read).layout
        let all = layout.frames(in: [UInt8](flac), base: 0, samples: 0...layout.totalSamples)
        let every10s = Int(10 * FLACClockFixture.sampleRate)
        var points: [UInt8] = []
        var next = 0
        for frame in all where frame.sample >= next {
            let fields = [UInt64(frame.sample), UInt64(frame.byte - layout.audioStart), 4096]
            points += fields.enumerated().flatMap { k, v in
                (0..<(k == 2 ? 2 : 8)).reversed().map { UInt8((v >> (8 * UInt64($0))) & 0xFF) }
            }
            next += every10s
        }
        points += [UInt8](repeating: 0xFF, count: 8) + [UInt8](repeating: 0, count: 10)   // a placeholder point
        var data = flac!
        data.insert(contentsOf: [0x03, 0, UInt8(points.count >> 8), UInt8(points.count & 0xFF)] + points, at: 42)

        let withTable = try await FLACStream.read(from: memory(data))
        XCTAssertEqual(try XCTUnwrap(withTable).layout.seekPoints.count, 9, "the placeholder is skipped")
        try await assertFinds(in: data)
    }

    func testFindsTheFrameBehindLargeCoverArt() async throws {
        var data = flac!
        let art = 3_000_000   // bigger than any read the finder makes
        data.insert(contentsOf: [0x06, UInt8(art >> 16), UInt8((art >> 8) & 0xFF), UInt8(art & 0xFF)]
                    + [UInt8](repeating: 0xFF, count: art), at: 42)   // a PICTURE right after STREAMINFO
        try await assertFinds(in: data)
    }

    func testASeekReadsOnlyAFewSmallPieces() async throws {
        let counter = Counter()
        let source = memory(flac, counter: counter)
        let read = try await FLACStream.read(from: source)
        let stream = try XCTUnwrap(read)
        counter.reads = 0
        _ = try await stream.start(at: 61.7, from: source)
        XCTAssertLessThanOrEqual(counter.reads, 8)
    }

    func testANonFLACStreamIsNotStartedMidTrack() async throws {
        let read = try await FLACStream.read(from: memory(FLACClockFixture.data(ext: "wav")))
        XCTAssertNil(read)
        let tiny = try await FLACStream.read(from: memory(Data("fLaC".utf8)))
        XCTAssertNil(tiny)
    }

    /// A read that fails says so: it's not an answer that the stream isn't a FLAC (the engine asks again).
    func testAFailedReadThrowsRatherThanSayingNotFLAC() async throws {
        struct Blip: Error {}
        let failing = FLACByteSource { _ in throw Blip() }
        do {
            _ = try await FLACStream.read(from: failing)
            XCTFail("a failed read returned an answer")
        } catch is Blip {}
        let read = try await FLACStream.read(from: memory(flac))
        do {
            _ = try await XCTUnwrap(read).start(at: 30, from: failing)
            XCTFail("a failed read found a start")
        } catch is Blip {}
    }

    /// A stream from mid-track is served by range requests: a server that answers every request
    /// with the whole file can't serve one.
    func testAServerWithoutRangesIsNotStartedMidTrack() async throws {
        let server = RangeFileServer(data: flac, honorsRanges: false)
        try server.start()
        defer { server.stop() }
        let read = try await FLACStream.read(from: server.byteSource)
        XCTAssertNil(read)
    }
}
