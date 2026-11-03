import XCTest
@testable import Kima

/// Long-form progress saves around the end of a book or episode: the server's last word is
/// "finished", and saves reach it in the order they were made.
@MainActor
final class PlaybackProgressTests: XCTestCase {

    override func tearDown() { StubURLProtocol.reset() }

    private func controller() -> PlaybackController {
        .stubbed()
    }

    private var oneFileBook: BookSession {
        BookSession(bookId: "b", totalDuration: 100, files: [AudiobookTrack(index: 1, startOffset: 0, duration: 100)])
    }

    private func pausedBook() -> PlaybackController {
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        let c = controller()
        c.playbackType = .audiobook(oneFileBook)
        c.currentLongFormFileIndex = 1
        c.longFormAPIClient = .stubbed()
        c.engine.status = .paused
        return c
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(400)) }

    // MARK: Finishing

    /// The pause at the end can be seen before or after the "file ended" event; either way the
    /// server's last word is "finished".
    func testFinishingABookIsTheLastSaveWhicheverWayThePauseLands() async throws {
        for pauseFirst in [true, false] {
            StubURLProtocol.reset()
            let c = pausedBook()
            c.lastSavedProgressTime = 90
            c.engine.currentTime = 99.4
            if pauseFirst { c.saveProgress() }
            c.finishAudiobook(session: oneFileBook)
            c.saveProgress()   // the pause, the resign observer, the 15 s timer: all after the finish
            try await settle()
            let saves = StubURLProtocol.posts(to: "/audiobooks/b/progress")
            XCTAssertEqual(saves.last?["isFinished"] as? Bool, true, "pauseFirst=\(pauseFirst)")
            XCTAssertEqual(saves.count, pauseFirst ? 2 : 1, "pauseFirst=\(pauseFirst)")
        }
    }

    func testFinishingAnEpisodeIsNotUndoneByThePauseAtTheEnd() async throws {
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        let c = controller()
        let ep = try Episode.fixture("e1")
        c.playbackType = .podcastEpisode(podcastId: "p", episode: ep, queue: [ep])   // last episode
        c.longFormAPIClient = .stubbed()
        c.lastSavedProgressTime = 1700
        c.engine.status = .paused
        c.engine.currentTime = 1799.6
        c.handlePodcastEpisodeEnded()
        c.saveProgress()
        try await settle()
        let saves = StubURLProtocol.posts(to: "/podcasts/p/episodes/e1/progress")
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves.last?["isFinished"] as? Bool, true)
    }

    func testSeekingInAFinishedBookSavesAgain() async throws {
        let c = pausedBook()
        c.finishAudiobook(session: oneFileBook)
        c.seek(to: 20)
        c.saveProgress()
        try await settle()
        let saves = StubURLProtocol.posts(to: "/audiobooks/b/progress")
        XCTAssertEqual(saves.map { $0["isFinished"] as? Bool }, [true, false])
        XCTAssertEqual(saves.last?["currentTime"] as? Double, 20)
    }

    func testNoSaveWhileTheNextFileIsLoading() async throws {
        let c = pausedBook()
        c.engine.currentTime = 50
        _ = c.engine.claimLoad()   // the engine still holds the previous file
        c.saveProgress()
        try await settle()
        XCTAssertTrue(StubURLProtocol.posts(to: "/progress").isEmpty)
    }
}
