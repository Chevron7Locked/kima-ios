import AVFoundation
import XCTest
@testable import Kima

/// A FLAC skip swaps in a new item, a moment of no sound the way a seek's buffering is. While
/// playing, the skip goes on showing playing: the lock screen and the play button don't drop to
/// paused and back, and no pause-time progress save fires. The user's pause or a call still shows,
/// and showing playing never outlasts the sound.
@MainActor
final class FLACSeekShownStateTests: FLACClockTestCase {

    func testASkipWhilePlayingKeepsShowingPlaying() async throws {
        await playing()
        let stateChanges = countStateChanges()
        await skipSwapped(to: 60)
        await waitUntil(10) { self.engine.player.timeControlStatus == .playing }
        try await Task.sleep(for: Self.settle)
        XCTAssertEqual(stateChanges(), 0, "the shown state flickered across the skip")
        XCTAssertTrue(engine.isPlaying)
        try await assertHeardAndShown(at: 61.5)
    }

    func testAPauseDuringASkipShowsPaused() async throws {
        await playing()
        await skipSwapped(to: 60)
        engine.pause()
        try await Task.sleep(for: Self.settle)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.player.rate, 0)
        XCTAssertEqual(engine.status, .paused)
    }

    func testACallDuringASkipShowsStopped() async throws {
        await playing()
        await skipSwapped(to: 60)
        beginInterruption()
        try await Task.sleep(for: Self.settle)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.player.rate, 0)
    }

    /// Skips in quick succession, the second while the first's swap is still quiet (the player
    /// paused at rate 0, as it reports one right after a swap): no flicker.
    func testQuickSkipsKeepShowingPlaying() async throws {
        await playing()
        let stateChanges = countStateChanges()
        server.delay = { _ in 1 }   // the first swap's stream takes a moment
        await skipSwapped(to: 60)
        engine.player.pause()   // the swap's moment of pause
        await waitUntil(5) { self.engine.status == .buffering }
        XCTAssertTrue(engine.isPlaying && engine.status == .buffering, "precondition: the first swap is still held")
        server.delay = { _ in 0 }
        await skipSwapped(to: 30)
        await waitUntil(10) { self.engine.player.timeControlStatus == .playing }
        try await Task.sleep(for: Self.settle)
        XCTAssertEqual(stateChanges(), 0, "the shown state flickered across the skips")
        try await assertHeardAndShown(at: 31.5)
    }

    /// Once the skipped-to spot plays, a pause the engine only hears from the player shows paused.
    func testAfterASkipPlaysAPlayerPauseShowsPaused() async throws {
        await playing()
        await skipSwapped(to: 60)
        await waitUntil(10) { self.engine.player.timeControlStatus == .playing }
        try await Task.sleep(for: Self.settle)
        engine.player.pause()
        await waitUntil(5) { !self.engine.isPlaying }
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.status, .paused)
    }

    /// Paused, a skip swaps the item quietly; play then starts the skipped-to spot.
    func testPlayAfterAPausedSkipPlaysTheSkip() async throws {
        await playing()
        engine.pause()
        await waitUntil(5) { self.engine.status == .paused }
        await skipSwapped(to: 60)
        await waitUntil(10) { self.engine.player.currentItem?.status == .readyToPlay }
        try await Task.sleep(for: Self.settle)
        XCTAssertEqual(engine.player.rate, 0)
        XCTAssertFalse(engine.isPlaying)
        engine.play()
        await waitUntil(10) { self.engine.status == .playing }
        try await assertHeardAndShown(at: 61.5)
    }
}
