import AVFoundation
import XCTest
@testable import Kima

/// The one recovery path for music, audiobooks and podcasts: a stall or a dropped stream is rebuilt
/// at the position it stopped, the lock screen is refreshed first, and repeated failures stop with
/// the place kept. The stream ticket comes from a stubbed server; no audio plays.
@MainActor
final class PlaybackRecoveryTests: XCTestCase {

    override func tearDown() { StubURLProtocol.reset() }

    /// API calls go to the stub; the stream host is a reserved address that never answers, so a
    /// rebuilt item stays loading instead of failing and starting another recovery.
    private func controller() -> PlaybackController {
        let c = PlaybackController.stubbed(baseURL: "https://192.0.2.1")
        StubURLProtocol.handler = { req in
            req.url?.path.hasSuffix("/auth/stream-ticket") == true
                ? (200, Data(#"{"ticket":"fresh","expiresIn":3600}"#.utf8))
                : (404, Data())
        }
        return c
    }

    /// Two files (book time 0–100, 100–200), `loaded` the one in the engine.
    private func book(loaded: Int) -> BookSession {
        BookSession(bookId: "b", totalDuration: 200, files: [
            AudiobookTrack(index: 1, startOffset: 0, duration: 100),
            AudiobookTrack(index: 2, startOffset: 100, duration: 100)], loadedFileIndex: loaded)
    }

    /// Waits for the rebuild's ticket fetch and load to land.
    private func landed(_ c: PlaybackController) async throws -> URL? {
        for _ in 0..<40 where c.engine.player.currentItem == nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        return (c.engine.player.currentItem?.asset as? AVURLAsset)?.url
    }

    /// The engine mid-play, as the watchdog sees it the moment it gives up.
    private func playingAndStuck(_ c: PlaybackController, at time: Double) {
        c.engine.status = .buffering
        c.engine.wantsPlayback = true
        c.engine.currentTime = time
        c.engine.currentLoadReachedReady = true
    }

    func testMusicStallRebuildsTheTrackAtItsPositionAndKeepsPlaying() async throws {
        let c = controller()
        c.apiClient = .stubbed()
        c.queue = [try Track.fixture("a"), try Track.fixture("b")]
        playingAndStuck(c, at: 42)
        var lockScreen = 0
        c.nowPlayingHook = { lockScreen += 1 }
        c.engine.giveUpOnStalledItem()
        XCTAssertGreaterThan(lockScreen, 0, "the lock screen is refreshed before the rebuild")
        let url = try await landed(c)
        XCTAssertEqual(url?.path, "/api/library/tracks/a/stream")
        XCTAssertEqual(url?.query, "token=fresh")
        XCTAssertEqual(c.engine.pendingSeek, 42)
        XCTAssertTrue(c.engine.wantsPlayback)
        XCTAssertEqual(c.currentIndex, 0, "a stall never skips")
        c.engine.clear()
    }

    func testAudiobookStallRebuildsTheRightFileAtTheBookPosition() async throws {
        let c = controller()
        c.playbackType = .audiobook(book(loaded: 2))
        c.longFormAPIClient = .stubbed()
        playingAndStuck(c, at: 30)
        var lockScreen = 0
        c.nowPlayingHook = { lockScreen += 1 }
        c.engine.giveUpOnStalledItem()
        XCTAssertGreaterThan(lockScreen, 0, "long-form refreshes the lock screen too")
        let url = try await landed(c)
        XCTAssertEqual(url?.path, "/api/audiobooks/b/stream")
        XCTAssertTrue(url?.query?.contains("trackIndex=2") == true)
        XCTAssertEqual(c.engine.pendingSeek, 30)
        XCTAssertTrue(c.engine.wantsPlayback)
        c.engine.clear()
    }

    func testPodcastDropRebuildsTheEpisodeAndStaysPausedIfPaused() async throws {
        let c = controller()
        let ep = try Episode.fixture("e1")
        c.playbackType = .podcastEpisode(podcastId: "p", episode: ep, queue: [ep])
        c.longFormAPIClient = .stubbed()
        c.engine.status = .paused
        c.engine.wantsPlayback = false
        c.engine.currentTime = 600
        c.engine.debugSimulateStreamDrop()
        let url = try await landed(c)
        XCTAssertEqual(url?.path, "/api/podcasts/p/episodes/e1/stream")
        XCTAssertEqual(c.engine.pendingSeek, 600)
        XCTAssertFalse(c.engine.wantsPlayback, "a paused episode comes back paused")
        c.engine.clear()
    }

    func testAnAudiobookFailingAtTheEndOfAFileRestartsAtTheTopOfTheNext() async throws {
        let c = controller()
        c.playbackType = .audiobook(book(loaded: 1))
        c.longFormAPIClient = .stubbed()
        playingAndStuck(c, at: 100)  // the end of file 1: book time 100 is file 2's top
        c.engine.giveUpOnStalledItem()
        let url = try await landed(c)
        XCTAssertTrue(url?.query?.contains("trackIndex=2") == true)
        XCTAssertNil(c.engine.pendingSeek, "file 2's top, not file 1's time read against file 2")
        c.engine.clear()
    }

    func testALoadThatFailsBeforePlayingRestartsWhereItWasAsked() {
        let c = controller()
        c.playbackType = .audiobook(book(loaded: 2))
        c.engine.pendingSeek = 55
        c.engine.currentTime = 0
        XCTAssertEqual(c.recoveryPoint, 155, "file 2 starts at 100; the resume seek never landed")
    }

    /// A track whose load (asked to start at 50) failed before ready, then the user skips: the
    /// rebuild starts at the skip, not the old resume. The top too, though the engine's 0 reads as
    /// "never played" and falls back to the last known position.
    func testASkipOnAFailedTrackIsWhereItsRebuildStarts() {
        let c = controller()
        c.lastKnownMusicPosition = 50   // the failed load's start
        c.engine.pendingSeek = 50
        c.engine.status = .error
        c.seek(to: 40)
        XCTAssertEqual(c.recoveryPoint, 40)
        c.seek(to: 0)
        XCTAssertEqual(c.recoveryPoint, 0, "the skip to the top, not the failed load's 50")
    }

    func testRepeatedStallsStopWithThePlaceKept() async throws {
        let c = controller()
        c.apiClient = .stubbed()
        c.queue = [try Track.fixture("a"), try Track.fixture("b")]
        for _ in 0..<c.maxRecoveryAttempts {
            playingAndStuck(c, at: 42)
            c.engine.giveUpOnStalledItem()
            XCTAssertNotEqual(c.engine.audioError, "playback keeps stalling. tap play to try again.")
        }
        playingAndStuck(c, at: 42.5)
        c.engine.giveUpOnStalledItem()
        XCTAssertEqual(c.engine.status, .error)
        XCTAssertEqual(c.engine.audioError, "playback keeps stalling. tap play to try again.")
        XCTAssertEqual(c.queue.count, 2)
        XCTAssertEqual(c.currentIndex, 0)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(c.engine.player.currentItem, "no earlier rebuild lands after the stop")
    }

    func testStallsAMinuteOfAudioApartEachGetAFreshBudget() throws {
        let c = controller()
        c.apiClient = .stubbed()
        c.queue = [try Track.fixture("a")]
        for minute in 0..<5 {
            playingAndStuck(c, at: Double(minute) * 61)
            c.engine.giveUpOnStalledItem()
            XCTAssertEqual(c.stallCount, 1)
        }
        c.engine.clear()
    }

    func testLongFormPastTheBudgetStopsInsteadOfLooping() throws {
        let c = controller()
        c.playbackType = .audiobook(book(loaded: 1))
        c.longFormAPIClient = .stubbed()
        for _ in 0..<c.maxRecoveryAttempts { XCTAssertTrue(c.consumeRecoveryBudget(at: 20)) }
        c.engine.currentTime = 20
        c.engine.currentLoadReachedReady = true
        c.engine.debugSimulateStreamDrop()
        XCTAssertEqual(c.engine.status, .error)
        XCTAssertEqual(c.engine.audioError, "couldn't play this. tap play to try again.")
        if case .audiobook = c.playbackType {} else { XCTFail("the book stays loaded") }
    }

    /// A music queue whose current track plays at 42.
    private func musicAt42(_ c: PlaybackController) throws {
        c.apiClient = .stubbed()
        c.queue = [try Track.fixture("a"), try Track.fixture("b")]
        playingAndStuck(c, at: 42)
    }

    /// An episode playing at 600.
    private func podcastAt600(_ c: PlaybackController) throws {
        let ep = try Episode.fixture("e1")
        c.playbackType = .podcastEpisode(podcastId: "p", episode: ep, queue: [ep])
        c.longFormAPIClient = .stubbed()
        playingAndStuck(c, at: 600)
    }

    /// The book's second file (book time 100–200) playing at 30 into the file.
    private func bookFile2At30(_ c: PlaybackController) throws {
        c.playbackType = .audiobook(book(loaded: 2))
        c.longFormAPIClient = .stubbed()
        playingAndStuck(c, at: 30)
    }

    /// Fails what `arrange` set playing, holds the rebuild's ticket fetch, runs `skip` while it is
    /// held, then lets the fetch answer and waits for the rebuilt item. The engine is cleared at
    /// teardown.
    private func skipDuringRebuildFetch(
        _ arrange: (PlaybackController) throws -> Void,
        _ skip: (PlaybackController) async -> Void
    ) async throws -> PlaybackController {
        let c = controller()
        addTeardownBlock { @MainActor in c.engine.clear() }
        let asked = expectation(description: "the rebuild asked for a ticket")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }  // an early exit must not leave the stub's queue blocked
        StubURLProtocol.handler = { req in
            guard req.url?.path.hasSuffix("/auth/stream-ticket") == true else { return (404, Data()) }
            asked.fulfill()
            gate.wait()
            return (200, Data(#"{"ticket":"fresh","expiresIn":3600}"#.utf8))
        }
        try arrange(c)
        c.engine.giveUpOnStalledItem()
        await fulfillment(of: [asked], timeout: 2)
        XCTAssertEqual(c.engine.status, .error, "the skip lands while the rebuild is still fetching")
        await skip(c)
        gate.signal()
        let url = try await landed(c)
        XCTAssertNotNil(url, "the rebuild loads")
        return c
    }

    func testASkipDuringTheRebuildsTicketFetchIsWhereTheTrackRestarts() async throws {
        let c = try await skipDuringRebuildFetch(musicAt42) { $0.seek(to: 40) }
        XCTAssertEqual(c.engine.pendingSeek, 40, "last skip wins")
    }

    func testASkipToTheTopDuringTheRebuildsTicketFetchRestartsAtTheTop() async throws {
        let c = try await skipDuringRebuildFetch(musicAt42) { $0.seek(to: 0) }
        XCTAssertNil(c.engine.pendingSeek, "the top, not the position the track failed at")
    }

    func testABackSkipPastTheTopDuringTheRebuildsTicketFetchRestartsAtTheTop() async throws {
        let c = try await skipDuringRebuildFetch(musicAt42) { c in
            c.skip(by: -60)  // the -30 s button twice: 42 back to the top
            await self.waitUntil(message: "the debounced skip never landed") { c.skipTask == nil }
        }
        XCTAssertNil(c.engine.pendingSeek, "the top, not the position the track failed at")
    }

    func testAPodcastSkipDuringTheRebuildsTicketFetchIsWhereTheEpisodeRestarts() async throws {
        let c = try await skipDuringRebuildFetch(podcastAt600) { $0.seek(to: 300) }
        XCTAssertEqual(c.engine.pendingSeek, 300, "last skip wins")
    }

    func testAPodcastSkipToTheTopDuringTheRebuildsTicketFetchRestartsAtTheTop() async throws {
        let c = try await skipDuringRebuildFetch(podcastAt600) { $0.seek(to: 0) }
        XCTAssertNil(c.engine.pendingSeek, "the top, not the position the episode failed at")
    }

    func testAnAudiobookSkipInTheSameFileDuringTheRebuildsTicketFetchIsWhereTheBookRestarts() async throws {
        let c = try await skipDuringRebuildFetch(bookFile2At30) { $0.seek(to: 150) }  // file 2, 50 in
        let url = (c.engine.player.currentItem?.asset as? AVURLAsset)?.url
        XCTAssertTrue(url?.query?.contains("trackIndex=2") == true, "the same file")
        XCTAssertEqual(c.engine.pendingSeek, 50, "last skip wins")
    }

    func testNoTicketBecauseTheSessionEndedSaysSo() async throws {
        let c = controller()
        c.apiClient = .stubbed()
        c.queue = [try Track.fixture("a")]
        StubURLProtocol.handler = { _ in (401, Data()) }
        c.loadCurrentTrack(autoplay: true)
        for _ in 0..<40 where c.engine.status != .error { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(c.engine.audioError, "session expired. please sign in again.")
    }

    func testNoTicketBecauseTheServerIsDownSaysSo() async throws {
        let c = controller()
        c.apiClient = .stubbed()
        c.queue = [try Track.fixture("a")]
        StubURLProtocol.handler = { _ in (503, Data()) }
        c.loadCurrentTrack(autoplay: true)
        for _ in 0..<40 where c.engine.status != .error { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(c.engine.audioError, "can't reach your server. tap play to try again.")
    }
}
