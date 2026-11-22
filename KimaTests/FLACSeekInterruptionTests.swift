import AVFoundation
import XCTest
@testable import Kima

/// A FLAC skip swaps in a new item. Only the user's play starts it: an engine the OS stopped
/// (an interruption) or one whose track failed stays stopped across the skip, and starts again
/// the way it would have without the skip.
@MainActor
final class FLACSeekInterruptionTests: FLACClockTestCase {

    /// A skip while stopped: the new item comes in and goes quiet. Nothing plays.
    private func assertTheSkipStaysStopped(at seconds: Double, file: StaticString = #filePath, line: UInt = #line) async throws {
        await skipSwapped(to: seconds, file: file, line: line)
        try await assertStaysSilentOnceReady(after: "the skip", file: file, line: line)
    }

    /// A call comes in: the OS pauses the player, the user still wants playback when it ends.
    func testASkipDuringAnInterruptionStaysStopped() async throws {
        await playing()
        beginInterruption()
        await waitUntil(5) { self.engine.status == .paused }
        try await assertTheSkipStaysStopped(at: 40)
        XCTAssertEqual(engine.status, .paused)
        XCTAssertEqual(engine.currentTime, 40, accuracy: 0.25)
    }

    /// The call ends with a resume: the skipped-to spot plays.
    func testACallEndingAfterASkipResumesAtTheSkip() async throws {
        await playing()
        beginInterruption()
        try await assertTheSkipStaysStopped(at: 40)
        engine.handleInterruption(.ended, shouldResume: true)
        await waitUntil(10) { self.engine.status == .playing }
        try await assertHeardAndShown(at: 41.5)
    }

    /// The interruption ended without a resume: tap-to-resume (`.blocked`) holds across a skip,
    /// and the user's play starts the skipped-to spot.
    func testASkipWhileBlockedStaysBlockedUntilPlay() async throws {
        await playing()
        beginInterruption()
        await waitUntil(5) { self.engine.status == .paused }
        engine.handleInterruption(.ended, shouldResume: false)
        XCTAssertEqual(engine.status, .blocked)
        try await assertTheSkipStaysStopped(at: 40)
        XCTAssertEqual(engine.status, .blocked)
        engine.play()
        await waitUntil(10) { self.engine.status == .playing }
        try await assertHeardAndShown(at: 41.5)
    }

    /// A call that begins while the track is still loading, and ends with a resume, plays it.
    func testACallDuringALoadResumesWhenItEnds() async throws {
        engine.load(url: server.url, autoplay: true)
        beginInterruption()
        XCTAssertEqual(engine.status, .paused)
        try await assertStaysSilentOnceReady(after: "a load mid-call")
        engine.handleInterruption(.ended, shouldResume: true)
        await waitUntil(10) { self.engine.status == .playing }
        try await assertHeardAndShown(at: 1.5)
    }

    /// A failed track isn't restarted by a skip: the skip is where recovery picks it up from.
    func testASkipOnAFailedTrackDoesNotRestartIt() async throws {
        await playing()
        engine.onFailed = { _ in }
        engine.debugSimulateStreamDrop()
        XCTAssertEqual(engine.status, .error)
        engine.seek(to: 40)
        try await Task.sleep(for: Self.settle)
        XCTAssertFalse(engine.isRestartedStream, "a dead track was restarted")
        XCTAssertFalse(engine.isFLACSeekInFlight)
        XCTAssertEqual(engine.currentTime, 40)
        XCTAssertEqual(engine.status, .error)
    }
}
