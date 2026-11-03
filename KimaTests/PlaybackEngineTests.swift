import AVFoundation
import XCTest
@testable import Kima

/// Engine timing and intent rules: the stall watchdog, interruptions, the resume seek, a refused
/// audio session, and late callbacks from an item a new load replaced. No audio plays.
@MainActor
final class PlaybackEngineTests: XCTestCase {

    private func engine(stallMs: Int = 200) -> PlaybackEngine {
        let e = PlaybackEngine()
        e.stallLimit = .milliseconds(stallMs)
        e.activateSession = { _ in }
        return e
    }

    /// The engine as if the user pressed play and the stream then stopped delivering.
    private func stalled(_ e: PlaybackEngine, at time: Double = 42) {
        e.status = .playing
        e.wantsPlayback = true
        e.currentTime = time
        e.applyTimeControlStatus(.waitingToPlayAtSpecifiedRate)
    }

    // MARK: Stall watchdog

    func testBufferingPastTheLimitGivesUpOnceAndKeepsTheIntent() async throws {
        let e = engine()
        var stalls = 0
        e.onStalled = { stalls += 1 }
        stalled(e)
        XCTAssertEqual(e.status, .buffering)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(stalls, 1)
        XCTAssertEqual(e.status, .error)
        XCTAssertEqual(e.audioError, "the stream timed out")
        XCTAssertTrue(e.wasPlayingBeforeFailure, "the rebuild must resume playing")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(stalls, 1, "an error state never re-arms")
    }

    func testPlaybackResumingBeforeTheLimitDisarms() async throws {
        let e = engine()
        var stalls = 0
        e.onStalled = { stalls += 1 }
        stalled(e)
        try await Task.sleep(for: .milliseconds(100))
        e.applyTimeControlStatus(.playing)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(stalls, 0)
        XCTAssertEqual(e.status, .playing)
    }

    func testPausedOrUnwantedPlaybackNeverArms() async throws {
        let e = engine()
        var stalls = 0
        e.onStalled = { stalls += 1 }
        e.status = .playing
        e.wantsPlayback = false
        e.applyTimeControlStatus(.waitingToPlayAtSpecifiedRate)
        e.status = .paused
        e.updateStallWatchdog()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(stalls, 0)
    }

    func testALoadThatNeverStartsCountsOnlyWithAutoplay() async throws {
        let e = engine()
        var stalls = 0
        e.onStalled = { stalls += 1 }
        e.status = .loading
        e.wantsPlayback = false
        e.updateStallWatchdog()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(stalls, 0, "a paused load waits quietly")
        e.wantsPlayback = true
        e.updateStallWatchdog()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(stalls, 1)
    }

    func testANewLoadClaimDropsTheTimer() async throws {
        let e = engine()
        var stalls = 0
        e.onStalled = { stalls += 1 }
        stalled(e)
        _ = e.claimLoad()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(stalls, 0, "the timer belonged to the replaced item")
    }

    func testProgressDuringTheWindowStartsANewWindow() async throws {
        let e = engine(stallMs: 300)
        var stalls = 0
        e.onStalled = { stalls += 1 }
        stalled(e, at: 10)
        try await Task.sleep(for: .milliseconds(150))
        e.currentTime = 15   // it played a little between buffers
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(stalls, 0, "time moved, so this window doesn't count")
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(stalls, 1, "stuck for a whole new window")
    }

    // MARK: Interruptions

    func testInterruptionResumesFromIntentEvenWhenKVOAlreadyPaused() {
        let e = engine()
        e.wantsPlayback = true
        e.status = .paused      // the KVO pause landed before the .began notification
        e.isPlaying = false
        e.handleInterruption(.began, shouldResume: false)
        e.handleInterruption(.ended, shouldResume: true)
        XCTAssertEqual(e.player.rate, 1, "play() was called")
        XCTAssertNotEqual(e.status, .blocked)
    }

    func testInterruptionLeavesAUserPauseAlone() {
        let e = engine()
        e.wantsPlayback = false
        e.status = .paused
        e.handleInterruption(.began, shouldResume: false)
        e.handleInterruption(.ended, shouldResume: true)
        XCTAssertEqual(e.player.rate, 0)
        XCTAssertEqual(e.status, .paused, "no tap-to-resume for something the user paused")
    }

    func testInterruptionWithoutResumeShowsTapToResume() {
        let e = engine()
        e.wantsPlayback = true
        e.status = .paused
        e.handleInterruption(.ended, shouldResume: false)
        XCTAssertEqual(e.status, .blocked)
        XCTAssertEqual(e.player.rate, 0)
    }

    func testInterruptionResumeWithRefusedSessionShowsTheError() {
        let e = engine()
        e.activateSession = { _ in throw NSError(domain: "test", code: 1) }
        e.wantsPlayback = true
        e.status = .paused
        e.handleInterruption(.ended, shouldResume: true)
        XCTAssertEqual(e.player.rate, 0)
        XCTAssertEqual(e.status, .error)
    }

    // MARK: Resume seek

    func testCancelledResumeSeekStillPlaysWhenWanted() {
        let e = engine()
        e.wantsPlayback = true
        e.finishResumeSeek(finished: false, target: 30, generation: e.generation)
        XCTAssertEqual(e.player.rate, 1)
    }

    func testTheResumePositionIsKeptUntilItsSeekLands() {
        let e = engine()
        e.pendingSeek = 55
        e.handleItemStatus(.readyToPlay, item: AVPlayerItem(url: URL(string: "https://stub.test/a.mp3")!),
                           generation: e.generation)
        XCTAssertEqual(e.pendingSeek, 55, "a failure before the seek lands must still resume at 55")
        e.finishResumeSeek(finished: true, target: 55, generation: e.generation)
        XCTAssertNil(e.pendingSeek)
    }

    func testResumeSeekForAnOlderItemIsDropped() {
        let e = engine()
        e.wantsPlayback = true
        e.status = .loading
        e.finishResumeSeek(finished: true, target: 30, generation: e.generation - 1)
        XCTAssertEqual(e.player.rate, 0)
        XCTAssertEqual(e.status, .loading)
    }

    func testPausedResumeSeekLandsPausedAtTheTarget() {
        let e = engine()
        e.wantsPlayback = false
        e.status = .loading
        e.finishResumeSeek(finished: true, target: 30, generation: e.generation)
        XCTAssertEqual(e.status, .paused)
        XCTAssertEqual(e.currentTime, 30)
        XCTAssertEqual(e.player.rate, 0)
    }

    // MARK: Audio session

    func testRefusedSessionStopsTheLoad() {
        let e = engine()
        e.activateSession = { _ in throw NSError(domain: "test", code: 1) }
        e.load(url: URL(string: "https://stub.test/a.mp3")!, autoplay: true, seekTo: 10)
        XCTAssertEqual(e.status, .error)
        XCTAssertEqual(e.audioError, "audio is unavailable. tap play to try again.")
        XCTAssertNil(e.player.currentItem, "nothing may load without the session")
        XCTAssertFalse(e.wantsPlayback)
    }

    // MARK: Late callbacks from a replaced item

    func testAnEndDuringTheNextLoadsTicketFetchIsDropped() async throws {
        let e = engine()
        var ends = 0
        e.onEnded = { ends += 1 }
        let item = AVPlayerItem(url: URL(string: "https://stub.test/a.mp3")!)
        e.setupItemObservers(item: item, generation: e.generation)
        _ = e.claimLoad()   // "next" was tapped; the ticket fetch is in flight
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(ends, 0, "the old song ending must not advance the queue a second time")
        e.teardownItemObservers()
    }

    func testAnEndWithNoLoadInFlightAdvances() async throws {
        let e = engine()
        var ends = 0
        e.onEnded = { ends += 1 }
        let item = AVPlayerItem(url: URL(string: "https://stub.test/a.mp3")!)
        e.setupItemObservers(item: item, generation: e.generation)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(ends, 1)
        e.teardownItemObservers()
    }

    func testLoadPendingOnlyBetweenAClaimAndItsLanding() {
        let e = engine()
        XCTAssertFalse(e.isLoadPending)
        _ = e.claimLoad()
        XCTAssertTrue(e.isLoadPending)
        e.signalExternalError("x")
        XCTAssertFalse(e.isLoadPending, "a teardown settles the claim")
        _ = e.claimLoad()
        e.clear()
        XCTAssertFalse(e.isLoadPending)
    }
}
