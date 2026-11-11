import XCTest
@testable import Kima

/// The yield rule (ticket 05): one shared rule stops any playing preview the moment main playback
/// becomes audible — including the fetching half. Seam: `ClipPreviewPlayer`'s public interface
/// (toggle / stop / previewingId) driven against a real controller's engine mirrors, per the
/// PlaybackAudibleTests idiom.
@MainActor
final class ClipPreviewYieldTests: XCTestCase {

    /// A controller whose host-audio noise is silenced: these tests drive the engine's mirrors by
    /// hand, and the clip genuinely plays inside the shared test host — so the session observers
    /// and the empty engine player's time-control KVO would move those mirrors mid-assertion
    /// (per PlaybackEngineTests' activateSession stub — no audio side effects).
    private func controller() -> PlaybackController {
        let c = PlaybackController(server: KimaServer(baseURL: URL(string: "http://test.local")!))
        for token in [c.engine.interruptionToken, c.engine.routeChangeToken] {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
        c.engine.timeControlObservation?.invalidate()
        c.engine.timeControlObservation = nil
        return c
    }

    /// Stops the clip after the test so a 60-second silent WAV doesn't serenade the rest of the suite.
    private func stopAfterTest(_ previewer: ClipPreviewPlayer) {
        addTeardownBlock { await MainActor.run { previewer.stop() } }
    }

    /// A valid 60-second silent WAV: loads and plays without failing inside the test window, and
    /// never reaches its end notification, so only the yield rule can stop it.
    private func silentClipURL() throws -> URL {
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

    /// Starts a preview through the public interface and proves it is running.
    private func startPreview(_ previewer: ClipPreviewPlayer, on player: PlaybackController) async throws {
        let url = try silentClipURL()
        await previewer.toggle(id: "clip-1", mainPlayer: player) { url }
        XCTAssertEqual(previewer.previewingId, "clip-1")
    }

    /// Main starts fetching — no byte has landed yet: the running clip is silenced before it can
    /// compete with sound that is on its way (the bug: watchers keyed on bare isPlaying let the
    /// preview keep sounding through the whole fetch).
    func testPreviewStopsWhenMainStartsFetching() async throws {
        let c = controller()
        let previewer = ClipPreviewPlayer()
        stopAfterTest(previewer)
        try await startPreview(previewer, on: c)

        c.engine.wantsPlayback = true
        c.engine.status = .loading
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertNil(previewer.previewingId, "the preview must yield the moment main goes audible (fetching counts)")
    }

    /// The playing half of audible: sound actually starts — the clip yields, and main keeps it
    /// (stopping the preview never pauses or resumes what the user just started; the new thing won).
    func testPreviewStopsWhenMainGoesAudibleAndNeverResumes() async throws {
        let c = controller()
        let previewer = ClipPreviewPlayer()
        stopAfterTest(previewer)
        c.engine.wantsPlayback = true                 // main genuinely audible before the clip
        c.engine.applyTimeControlStatus(.playing)
        try await startPreview(previewer, on: c)
        XCTAssertFalse(c.engine.wantsPlayback, "starting a preview pauses audible main")
        c.engine.applyTimeControlStatus(.paused)      // the engine reports the pause, as KVO does

        c.engine.wantsPlayback = true                 // the user resumes from the mini bar
        c.engine.applyTimeControlStatus(.playing)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertNil(previewer.previewingId)
        XCTAssertTrue(c.isPlaying, "yielding must leave main playing and not touch it")
    }
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
