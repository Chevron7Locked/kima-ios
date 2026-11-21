import Foundation

/// What a FLAC file says about itself, read from its metadata blocks: enough to find the frame that
/// holds a given moment and to write a header for a file that starts at that frame.
///
/// Why this exists: Apple's player seeks a FLAC by a byte estimate and reports the requested time
/// while decoding from wherever the estimate landed, seconds away, so the lyrics and the scrubber
/// read a clock that isn't what's heard. A FLAC whose frames start mid-track plays from its first
/// frame exactly, so the engine never asks the player to seek a FLAC (see `FLACStream.start(at:from:)`).
struct FLACLayout: Equatable {
    struct SeekPoint: Equatable {
        let sample: Int
        /// Bytes from the first frame.
        let offset: Int
    }

    /// The 34-byte STREAMINFO body.
    let streamInfo: [UInt8]
    /// Byte where the first frame starts.
    let audioStart: Int
    let seekPoints: [SeekPoint]

    var sampleRate: Int { Int(streamInfo[10]) << 12 | Int(streamInfo[11]) << 4 | Int(streamInfo[12]) >> 4 }
    var bitsPerSample: Int { (Int(streamInfo[12] & 1) << 4 | Int(streamInfo[13]) >> 4) + 1 }
    var maxBlockSize: Int { streamInfo[2...3].bigEndian }
    var maxFrameSize: Int { streamInfo[7...9].bigEndian }
    /// 0 when the encoder didn't know.
    var totalSamples: Int {
        Int(streamInfo[13] & 0x0F) << 32 | streamInfo[14...17].bigEndian
    }

    /// The header of a file that starts at the frame holding `sample`: the magic and STREAMINFO
    /// alone (the other blocks describe the whole file or don't matter to playback), with the sample
    /// count cut to what remains and the whole-file MD5 zeroed (zero means "not known").
    func header(startingAt sample: Int) -> Data {
        var info = streamInfo
        if totalSamples > 0 {
            let remaining = max(0, totalSamples - sample)
            info[13] = (info[13] & 0xF0) | UInt8((remaining >> 32) & 0x0F)
            for k in 0..<4 { info[14 + k] = UInt8((remaining >> (24 - 8 * k)) & 0xFF) }
        }
        for k in 18..<34 { info[k] = 0 }
        return Data("fLaC".utf8) + Data([0x80, 0, 0, 34]) + Data(info)   // 0x80: last block, type STREAMINFO
    }

    // MARK: - Frames

    /// The frame header starting at `i`, if one does: its first sample. Checks every field the
    /// format fixes and the header's CRC-8, so a sync-like pattern inside audio data is rejected.
    func frameSample(in b: [UInt8], at i: Int) -> Int? {
        guard i + 6 <= b.count, b[i] == 0xFF, b[i + 1] & 0xFE == 0xF8 else { return nil }
        let variable = b[i + 1] & 1 == 1
        let blockCode = b[i + 2] >> 4, rateCode = b[i + 2] & 0x0F
        let channels = b[i + 3] >> 4, sizeCode = (b[i + 3] >> 1) & 7
        guard blockCode != 0, rateCode != 0x0F, channels <= 10, b[i + 3] & 1 == 0, sizeCode != 3 else { return nil }
        let sizes: [UInt8: Int] = [1: 8, 2: 12, 4: 16, 5: 20, 6: 24, 7: 32]
        if sizeCode != 0, sizes[sizeCode] != bitsPerSample { return nil }

        // The frame (fixed block size) or sample (variable) number, UTF-8 style.
        var j = i + 4
        let lead = b[j]
        let extra: Int
        var value: Int
        switch lead {
        case 0x00...0x7F: extra = 0; value = Int(lead)
        case 0xC0...0xDF: extra = 1; value = Int(lead & 0x1F)
        case 0xE0...0xEF: extra = 2; value = Int(lead & 0x0F)
        case 0xF0...0xF7: extra = 3; value = Int(lead & 0x07)
        case 0xF8...0xFB: extra = 4; value = Int(lead & 0x03)
        case 0xFC...0xFD: extra = 5; value = Int(lead & 0x01)
        case 0xFE:        extra = 6; value = 0
        default: return nil
        }
        guard j + 1 + extra < b.count else { return nil }
        for k in 1...max(1, extra) where extra > 0 {
            guard b[j + k] & 0xC0 == 0x80 else { return nil }
            value = value << 6 | Int(b[j + k] & 0x3F)
        }
        j += 1 + extra
        if blockCode == 6 { j += 1 } else if blockCode == 7 { j += 2 }
        if rateCode == 12 { j += 1 } else if rateCode == 13 || rateCode == 14 { j += 2 }
        guard j < b.count, Self.crc8(b[i..<j]) == b[j] else { return nil }
        return variable ? value : value * maxBlockSize
    }

    /// Every frame header in `b` (whose first byte is file byte `base`) with a first sample inside
    /// `samples`, in order, each starting later in time than the one before.
    func frames(in b: [UInt8], base: Int, samples: ClosedRange<Int>) -> [(byte: Int, sample: Int)] {
        var found: [(byte: Int, sample: Int)] = []
        var i = 0
        while i + 1 < b.count {
            if b[i] == 0xFF, let s = frameSample(in: b, at: i), samples.contains(s), s > (found.last?.sample ?? -1) {
                found.append((base + i, s))
            }
            i += 1
        }
        return found
    }

    private static func crc8(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 { crc = crc & 0x80 != 0 ? (crc << 1) ^ 0x07 : crc << 1 }
        }
        return crc
    }
}

extension Collection where Element == UInt8 {
    /// The bytes as one unsigned number, most significant first: FLAC's byte order.
    var bigEndian: Int { reduce(0) { $0 << 8 | Int($1) } }
}
