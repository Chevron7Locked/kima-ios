import Foundation
@testable import Kima

// The audio-test isolation seam (ticket 06 addendum): tests that drive real audio in the shared
// simulator host take their controller from here, so host-audio quiet is the default — the engine
// retires its own host-facing observers (`detachHostObservers`) instead of each test reaching
// into the plumbing by hand. Lifted from ClipPreviewYieldTests, where two flake rounds came from
// exactly that.

extension PlaybackController {
    /// A controller whose host-audio noise is silenced: these tests drive the engine's mirrors by
    /// hand, and a clip genuinely plays inside the shared test host — so the session observers
    /// and the engine player's time-control KVO would move those mirrors mid-assertion if left
    /// attached (per PlaybackEngineTests' activateSession stub — no audio side effects).
    static func silent() -> PlaybackController {
        let c = PlaybackController(server: KimaServer(baseURL: URL(string: "http://test.local")!))
        c.engine.detachHostObservers()
        return c
    }
}

/// A valid 60-second silent WAV: loads and plays without failing inside the test window, and
/// never reaches its end notification, so only the rule under test can stop it.
func makeSilentClipURL() throws -> URL {
    let count = 8_000 * 60 // 8-bit mono at 8 kHz
    var data = Data()
    data.append(contentsOf: "RIFF".utf8)
    data.appendLE32(36 + count)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    data.appendLE32(16)
    data.appendLE16(1)            // PCM
    data.appendLE16(1)            // mono
    data.appendLE32(8_000)        // sample rate
    data.appendLE32(8_000)        // byte rate
    data.appendLE16(1)            // block align
    data.appendLE16(8)            // bits per sample
    data.append(contentsOf: "data".utf8)
    data.appendLE32(count)
    data.append(Data(repeating: 0x80, count: count)) // u8 silence
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("clip-\(UUID().uuidString).wav")
    try data.write(to: url)
    return url
}

private extension Data {
    mutating func appendLE32(_ value: Int) {
        for shift in stride(from: 0, through: 24, by: 8) {
            append(UInt8((value >> shift) & 0xFF))
        }
    }

    mutating func appendLE16(_ value: Int) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }
}
