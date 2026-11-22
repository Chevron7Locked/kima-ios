import AVFoundation
import XCTest
@testable import Kima

/// Which file of a multi-file audiobook the player loads: a seek into another file loads that file
/// at its time, a seek within the loaded file loads nothing, and a file's end loads the next from its
/// top. The stream ticket comes from a stubbed server; the stream host never answers, so no audio plays.
@MainActor
final class AudiobookFileTests: XCTestCase {

    override func tearDown() { StubURLProtocol.reset() }

    /// A book of two files (book time 0–100, 100–200) with file 1 loaded and playing at 40.
    private func playingFile1At40() -> PlaybackController {
        let c = PlaybackController.stubbed(baseURL: "https://192.0.2.1")
        StubURLProtocol.handler = { req in
            req.url?.path.hasSuffix("/auth/stream-ticket") == true
                ? (200, Data(#"{"ticket":"fresh","expiresIn":3600}"#.utf8))
                : (200, Data("{}".utf8))
        }
        c.playbackType = .audiobook(BookSession(bookId: "b", totalDuration: 200, files: [
            AudiobookTrack(index: 1, startOffset: 0, duration: 100),
            AudiobookTrack(index: 2, startOffset: 100, duration: 100)], loadedFileIndex: 1))
        c.longFormAPIClient = .stubbed()
        c.engine.status = .playing
        c.engine.currentTime = 40
        addTeardownBlock { @MainActor in c.engine.clear() }
        return c
    }

    private func loadedURL(_ c: PlaybackController) async -> URL? {
        await waitUntil { c.engine.player.currentItem != nil }
        return (c.engine.player.currentItem?.asset as? AVURLAsset)?.url
    }

    func testASeekIntoTheNextFileLoadsItAtItsTime() async {
        let c = playingFile1At40()
        c.seek(to: 130)
        let url = await loadedURL(c)
        XCTAssertTrue(url?.query?.contains("trackIndex=2") == true, "\(String(describing: url))")
        XCTAssertEqual(c.engine.pendingSeek, 30)
        c.engine.currentTime = 30
        XCTAssertEqual(c.currentTime, 130, "the engine's time reads against the file now loaded")
    }

    func testASeekWithinTheLoadedFileLoadsNothing() async {
        let c = playingFile1At40()
        c.seek(to: 70)
        // No new stream for a seek within the file. 0.3 s covers the load's one stub round trip: a
        // cross-file seek planted here (to 130) loaded within it and failed (2026-11-22).
        await waitUntil(0.3, message: "a seek within the file loaded a stream", expectTimeout: true) {
            c.engine.player.currentItem != nil
        }
        c.engine.currentTime = 70
        XCTAssertEqual(c.currentTime, 70)
    }

    func testAFilesEndLoadsTheNextFromItsTop() async {
        let c = playingFile1At40()
        c.handleEnded()
        let url = await loadedURL(c)
        XCTAssertTrue(url?.query?.contains("trackIndex=2") == true, "\(String(describing: url))")
        XCTAssertNil(c.engine.pendingSeek, "the next file starts at its top")
        c.engine.currentTime = 5
        XCTAssertEqual(c.currentTime, 105)
    }
}
