import XCTest
@testable import Kima

/// The yield rule (ticket 05): one shared rule stops any playing preview the moment main playback
/// becomes audible — including the fetching half. Seam: `ClipPreviewPlayer`'s public interface
/// (toggle / stop / previewingId) driven against a real controller's engine mirrors, per the
/// PlaybackAudibleTests idiom.
@MainActor
final class ClipPreviewYieldTests: XCTestCase {

    // The silenced controller and the silent WAV are the shared audio-test seam —
    // PlaybackController.silent() / makeSilentClipURL() in Support/SilentTestHost.swift.

    /// Stops the clip after the test so a 60-second silent WAV doesn't serenade the rest of the suite.
    private func stopAfterTest(_ previewer: ClipPreviewPlayer) {
        addTeardownBlock { await MainActor.run { previewer.stop() } }
    }

    /// Starts a preview through the public interface and proves it is running.
    private func startPreview(_ previewer: ClipPreviewPlayer, on player: PlaybackController) async throws {
        let url = try makeSilentClipURL()
        await previewer.toggle(id: "clip-1", mainPlayer: player) { url }
        XCTAssertEqual(previewer.previewingId, "clip-1")
    }

    /// Main starts fetching — no byte has landed yet: the running clip is silenced before it can
    /// compete with sound that is on its way (the bug: watchers keyed on bare isPlaying let the
    /// preview keep sounding through the whole fetch).
    func testPreviewStopsWhenMainStartsFetching() async throws {
        let c = PlaybackController.silent()
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
        let c = PlaybackController.silent()
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
