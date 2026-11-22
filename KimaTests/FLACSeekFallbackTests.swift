import AVFoundation
import XCTest
@testable import Kima

/// A FLAC skip restarts the stream mid-track (`FLACTailLoader`). When that stream fails or stalls,
/// the engine puts the whole track back at the same spot instead of handing it to the recovery
/// ladder, which would rebuild it, restart it and fail again, round and round.
@MainActor
final class FLACSeekFallbackTests: FLACClockTestCase {

    /// A playing engine whose own reads answer the stream from the frame holding 60 s as `reply` says;
    /// the header and the frame search are served. AVPlayer's whole-track reads take `server`.
    private func playingWithTheRestartAt60(_ reply: RangeFileURLProtocol.Reply) async throws {
        let read = try await FLACStream.read(from: server.byteSource)
        let found = try await XCTUnwrap(read).start(at: 60, from: server.byteSource)
        let start = try XCTUnwrap(found)
        XCTAssertFalse(server.ranges.contains { $0.lowerBound == start.byte }, "precondition: finding the frame doesn't read from it")
        RangeFileURLProtocol.serve(try FLACClockFixture.data()) { $0.lowerBound == start.byte ? reply : .serve }
        engine.clear()
        engine = makeEngine(sessions: RangeFileURLProtocol.Factory())
        await playing()
    }

    /// Skips to 60, whose restarted stream won't play: the whole track comes back near the skip,
    /// playing, with no failure or stall reaching the recovery ladder.
    private func assertTheSkipFallsBackToTheWholeTrack(file: StaticString = #filePath, line: UInt = #line) async throws {
        var handedToTheLadder = 0
        engine.onFailed = { _ in handedToTheLadder += 1 }
        engine.onStalled = { handedToTheLadder += 1 }
        let stateChanges = countStateChanges()
        engine.seek(to: 60)
        await waitUntil(5) { self.engine.isRestartedStream }
        XCTAssertTrue(engine.isRestartedStream, "the skip restarted the stream", file: file, line: line)
        await waitUntil(10) { !self.engine.isRestartedStream && self.engine.status == .playing }
        XCTAssertEqual(handedToTheLadder, 0, file: file, line: line)
        XCTAssertEqual(stateChanges(), 0, "the shown state flickered across the fallback", file: file, line: line)
        XCTAssertEqual(engine.status, .playing, file: file, line: line)
        XCTAssertEqual(engine.duration, 90, accuracy: 0.1, file: file, line: line)
        let heard = try await heard()
        XCTAssertGreaterThan(heard, 50, "played on near the skip, not from the top: \(heard)", file: file, line: line)
    }

    /// The load stops restarting: the next skip seeks the item.
    func testARestartedStreamThatFailsFallsBackToTheWholeTrack() async throws {
        try await playingWithTheRestartAt60(.refuse)
        try await assertTheSkipFallsBackToTheWholeTrack()

        let reads = RangeFileURLProtocol.ranges.count
        engine.seek(to: 30)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        XCTAssertFalse(engine.isRestartedStream)
        XCTAssertEqual(RangeFileURLProtocol.ranges.count, reads, "the next skip tried to restart again")
    }

    /// A restarted stream that stops sending is the same dead end as one that fails: the stall
    /// watchdog puts the whole track back too, rather than the ladder's rebuild-and-restart loop.
    func testARestartedStreamThatStallsFallsBackToTheWholeTrack() async throws {
        try await playingWithTheRestartAt60(.hang)
        engine.stallLimit = .seconds(1)
        try await assertTheSkipFallsBackToTheWholeTrack()
    }

    /// The swap's held playing ends when no sound ever comes: the restarted stream and the whole
    /// track both stop sending. The hold is buffering to the engine, so the stall watchdog bounds it
    /// (one window for the restart, one for the fallback); then the track goes to the ladder, stopped.
    func testTheSwapsHeldPlayingEndsWhenTheSkipNeverPlays() async throws {
        try await playingWithTheRestartAt60(.hang)
        engine.stallLimit = .seconds(1)
        var stalls = 0
        engine.onStalled = { stalls += 1 }
        server.delay = { _ in 30 }   // the whole track's reads hang too (past the test; teardown doesn't wait on them)
        await skipSwapped(to: 60)
        XCTAssertTrue(engine.isPlaying, "precondition: the skip shows playing")
        await waitUntil(3) { !self.engine.isRestartedStream }
        XCTAssertFalse(engine.isRestartedStream, "the restart's stall fell back to the whole track")
        XCTAssertTrue(engine.isPlaying, "the hold dropped before the fallback had its chance")
        // One more 1 s stall window, then the give-up; 3 s leaves room for the main-actor hops under load.
        await waitUntil(3) { !self.engine.isPlaying }
        XCTAssertFalse(engine.isPlaying, "still shown playing with no sound")
        XCTAssertEqual(engine.status, .error)
        XCTAssertEqual(stalls, 1, "the dead track reaches the recovery ladder once")
    }

    /// Paused, the skip's failed stream falls back quietly: nothing plays until the user's play.
    func testAFallBackWhilePausedStaysPaused() async throws {
        try await playingWithTheRestartAt60(.refuse)
        engine.pause()
        await waitUntil(5) { self.engine.status == .paused }
        engine.seek(to: 60)
        await waitUntil(5) { self.engine.isRestartedStream }
        await waitUntil(10) { !self.engine.isRestartedStream && self.engine.player.currentItem?.status == .readyToPlay }
        try await Task.sleep(for: Self.settle)
        XCTAssertEqual(engine.player.rate, 0, "the fallback started playback")
        XCTAssertEqual(engine.status, .paused)
        engine.play()
        await waitUntil(10) { self.engine.status == .playing }
        let heard = try await heard()
        // The whole track takes the item's own seek, seconds near the skip in a FLAC.
        XCTAssertGreaterThan(heard, 50, "played near the skip, not from the top: \(heard)")
    }

    /// Blocked (a call ended without a resume), the fallback stays blocked: only play starts it.
    func testAFallBackWhileBlockedStaysBlocked() async throws {
        try await playingWithTheRestartAt60(.refuse)
        beginInterruption()
        engine.handleInterruption(.ended, shouldResume: false)
        engine.seek(to: 60)
        await waitUntil(5) { self.engine.isRestartedStream }
        await waitUntil(10) { !self.engine.isRestartedStream && self.engine.player.currentItem?.status == .readyToPlay }
        try await Task.sleep(for: Self.settle)
        XCTAssertEqual(engine.player.rate, 0, "the fallback started playback")
        XCTAssertEqual(engine.status, .blocked)
    }

    /// A restarted stream that played, then dropped: the player reports paused before the item
    /// fails. The user still wants it playing, so the whole track comes back playing.
    func testARestartedStreamThatDropsMidPlayComesBackPlaying() async throws {
        await playing()
        await skipSwapped(to: 60)
        await waitUntil(10) { self.engine.player.currentItem?.status == .readyToPlay && self.engine.player.timeControlStatus == .playing }
        try await Task.sleep(for: Self.settle)
        engine.player.pause()   // the drop's pause, ahead of its failure
        await waitUntil(5) { self.engine.status == .paused }
        XCTAssertEqual(engine.status, .paused, "precondition: the player's pause shows")
        engine.handleItemStatus(.failed, item: try XCTUnwrap(engine.player.currentItem), generation: engine.generation)
        await waitUntil(10) { !self.engine.isRestartedStream && self.engine.status == .playing }
        XCTAssertEqual(engine.status, .playing, "the drop stopped playback the user wanted")
        let heard = try await heard()
        XCTAssertGreaterThan(heard, 50, "played on near the skip: \(heard)")
    }

    /// Long-form speed survives the fallback: it reaches playing the way a resume does, which is
    /// where the controller puts the speed back (`play()` resets the rate to 1×).
    func testAFallBackKeepsThePlaybackSpeed() async throws {
        try await playingWithTheRestartAt60(.refuse)
        engine.onPlaying = { [unowned self] in self.engine.player.rate = 1.5 }   // the controller's re-assert
        engine.player.rate = 1.5
        try await Task.sleep(for: Self.settle)
        try await assertTheSkipFallsBackToTheWholeTrack()
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(engine.player.rate, 1.5)
    }

    /// A skip while the whole track is coming back wins over the spot it's coming back to, for
    /// playing and for recovering if it fails before it's ready. The whole track takes the item's
    /// own seek, which in a FLAC lands seconds near, not on, the skip.
    func testASkipDuringTheFallBackLandsAtTheSkip() async throws {
        try await playingWithTheRestartAt60(.refuse)
        engine.seek(to: 60)
        await waitUntil(5) { self.engine.flacSeek.loader != nil }
        server.delay = { _ in 1 }   // the whole track takes a moment to come back
        await waitUntil(10) { self.engine.flacSeek.loader == nil }
        XCTAssertNotEqual(engine.player.currentItem?.status, .readyToPlay, "precondition: the whole track is still coming back")
        engine.seek(to: 30)
        XCTAssertEqual(engine.pendingSeek, 30, "a failure before ready would recover at the old spot (recoveryPoint)")
        server.delay = { _ in 0 }
        await waitUntil(10) { self.engine.status == .playing }
        try await Task.sleep(for: .seconds(1.2))
        let heard = try await heard()
        XCTAssertEqual(heard, 31.5, accuracy: 6, "played from the skip, not the spot before it: \(heard)")
        XCTAssertNil(engine.pendingSeek)
    }

    /// A skip to the top before a saved-position load is ready leaves no position to resume at:
    /// recovery reads `pendingSeek`, and a load stores the top as none.
    func testASkipToTheTopBeforeReadyLeavesNoResume() async throws {
        engine.load(url: server.url, autoplay: true, seekTo: 50)
        engine.seek(to: 0)
        XCTAssertNil(engine.pendingSeek)
        await waitUntil(10) { self.engine.status == .playing }
        try await assertHeardAndShown(at: 1.5)
    }
}
