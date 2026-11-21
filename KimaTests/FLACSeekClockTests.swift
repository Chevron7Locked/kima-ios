import AVFoundation
import XCTest
@testable import Kima

/// Lyrics desync on skip: after a seek in a FLAC stream, Apple's player decoded from a byte
/// estimate seconds away from the target while reporting the target, so everything reading the
/// engine's clock (lyrics, scrubber, lock screen) was seconds off what was heard. These tests listen
/// to the audio itself (a self-timestamping fixture) and hold the shown time to it.
@MainActor
final class FLACSeekClockTests: FLACClockTestCase {

    func testAfterASkipTheShownTimeIsTheTimeHeard() async throws {
        engine.load(url: server.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
        XCTAssertEqual(engine.status, .playing)

        for target in [60.0, 25.0, 75.0] {
            engine.seek(to: target)
            await waitUntil(5) { !self.engine.isFLACSeekInFlight }
            await waitUntil(10) { self.engine.status == .playing && self.engine.player.currentItem?.status == .readyToPlay }
            try await Task.sleep(for: .seconds(2.2))   // two ticks: currentTime is the 1 Hz mirror
            let heard = try await heard()
            let shown = engine.currentTime
            // The 1 Hz mirror trails by up to a second, and the tap reads a little ahead of output.
            XCTAssertEqual(shown, heard, accuracy: 1.3, "skip to \(target): shown \(shown), heard \(heard)")
            XCTAssertEqual(heard, target + 2.5, accuracy: 1.5, "skip to \(target) landed at \(heard)")
            XCTAssertEqual(engine.duration, 90, accuracy: 0.1, "the whole track's length, not what's left")
        }
    }

    /// Recovery and restored sessions load at a saved position: that lands where it was asked too.
    func testALoadAtASavedPositionStartsThere() async throws {
        engine.load(url: server.url, autoplay: true, seekTo: 50)
        await waitUntil(10) { self.engine.status == .playing }
        try await assertHeardAndShown(at: 51.5)
        XCTAssertNil(engine.pendingSeek)
    }

    /// Previous / restart seek to 0: after a skip, that's the track's real start again.
    func testRestartAfterASkipPlaysFromTheTop() async throws {
        engine.load(url: server.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
        engine.seek(to: 70)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        engine.seek(to: 0)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        await waitUntil(10) { self.engine.status == .playing }
        try await assertHeardAndShown(at: 1.5)
        XCTAssertEqual(engine.duration, 90, accuracy: 0.1)
    }

    /// Two quick skips (a double tap on +15, a scrub let go twice): the second one wins.
    func testTheLastSkipWins() async throws {
        engine.load(url: server.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
        engine.seek(to: 30)
        engine.seek(to: 70)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        await waitUntil(10) { self.engine.status == .playing }
        try await assertHeardAndShown(at: 71.5)
    }

    /// The queue advances on the item's end: a track skipped near its end still ends, once.
    func testATrackSkippedNearItsEndStillEnds() async throws {
        var ends = 0
        engine.onEnded = { ends += 1 }
        engine.load(url: server.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
        engine.seek(to: 87)
        await waitUntil(10) { ends > 0 }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(ends, 1)
    }

    /// Anything but FLAC seeks the item as before: no restarted stream.
    func testAStreamThatIsNotFLACSeeksTheItem() async throws {
        let wav = try wavServer()
        try wav.start()
        defer { wav.stop() }
        engine.load(url: wav.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
        engine.seek(to: 60)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        XCTAssertNil(engine.flacSeek.loader)
        XCTAssertEqual(engine.flacSeek.startOffset, 0)
        try await assertHeardAndShown(at: 61.5)
    }

    /// Only a FLAC's header is read: a podcast's skip doesn't wait on the server for it.
    func testASkipInAnotherFormatDoesNotReadTheHeader() async throws {
        let wav = try wavServer()
        wav.delay = { $0 == 0...16_383 ? 3 : 0 }
        try wav.start()
        defer { wav.stop() }
        engine.load(url: wav.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
        engine.seek(to: 60)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        XCTAssertFalse(wav.ranges.contains(0...16_383), "asked for a FLAC header: \(wav.ranges)")
    }

    /// A track resumed at its saved spot and skipped while the resume was still out, when finding
    /// the FLAC's frames fails (a blip) and both fall back to the item's seek: it plays, from the skip.
    func testASkipDuringAResumePlaysFromTheSkip() async throws {
        server.delay = { $0 == 0...16_383 ? 1.5 : 0 }
        server.refuse = { $0 == 0...16_383 }
        engine.load(url: server.url, autoplay: true, seekTo: 50)
        await waitUntil(10) { self.engine.isFLACSeekInFlight }
        XCTAssertTrue(engine.isFLACSeekInFlight, "the resume should be waiting on the header")
        engine.seek(to: 20)
        await waitUntil(10) { self.engine.status == .playing }
        XCTAssertEqual(engine.status, .playing)
        XCTAssertNil(engine.pendingSeek)
        XCTAssertNil(engine.flacSeek.loader)
    }

    /// A blip while finding out the stream is a FLAC isn't an answer: the next skip asks again.
    func testAFailedCheckIsAskedAgainOnTheNextSkip() async throws {
        var refused = false
        server.refuse = { range in
            guard range == 0...16_383, !refused else { return false }
            refused = true
            return true
        }
        engine.load(url: server.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
        engine.seek(to: 60)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        XCTAssertTrue(refused)
        XCTAssertNil(engine.flacSeek.loader, "the check failed: the item seeks as before")

        engine.seek(to: 30)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        XCTAssertNotNil(engine.flacSeek.loader, "the second skip found the FLAC")
        await waitUntil(10) { self.engine.status == .playing }
        let heard = try await heard()
        XCTAssertEqual(heard, 30.5, accuracy: 1.2, "landed at \(heard)")
    }

    /// Long-form speed (an audiobook at 1.5×) is the player's rate: a skip keeps it.
    func testASkipKeepsThePlaybackSpeed() async throws {
        engine.load(url: server.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
        engine.player.rate = 1.5
        // AVPlayer reports its earlier 1× for a moment after the start: let the new speed settle.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(engine.player.rate, 1.5, "precondition: playing at 1.5×")
        engine.seek(to: 40)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        XCTAssertNotNil(engine.flacSeek.loader)
        await waitUntil(10) { self.engine.status == .playing && self.engine.player.rate > 0 }
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(engine.player.rate, 1.5)
    }

    /// A skip tapped while a saved-position load is still loading replaces the saved position.
    func testASkipBeforeTheResumeIsReadyLandsAtTheSkip() async throws {
        engine.load(url: server.url, autoplay: true, seekTo: 50)
        engine.seek(to: 20)
        await waitUntil(10) { self.engine.status == .playing && !self.engine.isFLACSeekInFlight }
        try await assertHeardAndShown(at: 21.5)
        XCTAssertNil(engine.pendingSeek)
    }

    /// After a skip the item starts mid-track, so a skip back before that start can only restart the
    /// stream. When that fails, the clock shows where the sound really is, not the skip asked for.
    func testABackwardSkipThatCantRestartShowsWhereItPlays() async throws {
        engine.load(url: server.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
        engine.seek(to: 60)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        let start = try XCTUnwrap(engine.flacSeek.loader).start
        await waitUntil(10) { self.engine.status == .playing }
        engine.pause()   // paused, the 1 Hz clock can't correct what the skip shows
        await waitUntil(5) { self.engine.status == .paused }
        server.refuse = { $0.lowerBound < start.byte }   // finding an earlier frame fails
        engine.seek(to: 20)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(engine.currentTime, 60, accuracy: 0.25, "the stream's start is as early as it goes")

        engine.play()
        await waitUntil(10) { self.engine.status == .playing }
        let heard = try await heard()
        XCTAssertEqual(heard, 60.5, accuracy: 1.2, "played on from \(heard)")
    }

    /// A speed chosen while a skip's stream is loading is the speed it plays at.
    func testASpeedChangedDuringASkipHolds() async throws {
        engine.load(url: server.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
        engine.player.rate = 1.5
        try await Task.sleep(for: .milliseconds(500))
        nonisolated(unsafe) var slow = false
        server.delay = { _ in slow ? 1 : 0 }
        engine.seek(to: 40)
        await waitUntil(5) { self.engine.flacSeek.loader != nil }
        slow = true                     // the new stream's reads take a moment
        engine.player.rate = 2          // what the speed control does while the engine buffers
        await waitUntil(10) { self.engine.status == .playing && self.engine.player.currentItem?.status == .readyToPlay }
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(engine.player.rate, 2)
    }

    /// A load's ready resets the recovery budget and warms the next track. A skip's restarted stream
    /// is the same load, so its ready does neither.
    func testASkipIsNotANewLoad() async throws {
        var readies = 0
        engine.onReady = { readies += 1 }
        engine.load(url: server.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
        engine.seek(to: 60)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        XCTAssertNotNil(engine.flacSeek.loader)
        await waitUntil(10) { self.engine.status == .playing && self.engine.player.currentItem?.status == .readyToPlay }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(readies, 1)
    }

    /// A skip while the resume's own restart is out, both finding their frames: it plays from the skip.
    func testASkipDuringAResumeRestartPlaysFromTheSkip() async throws {
        server.delay = { $0 == 0...16_383 ? 1 : 0 }
        engine.load(url: server.url, autoplay: true, seekTo: 50)
        await waitUntil(10) { self.engine.isFLACSeekInFlight }
        XCTAssertTrue(engine.isFLACSeekInFlight, "the resume should be waiting on the header")
        engine.seek(to: 20)
        await waitUntil(10) { !self.engine.isFLACSeekInFlight && self.engine.status == .playing }
        try await assertHeardAndShown(at: 21.5)
        XCTAssertNil(engine.pendingSeek)
    }

    /// A skip to the top while a resume's restarted stream is still loading plays from the top: that
    /// item starts mid-track, so its own start isn't the top.
    func testASkipToTheTopDuringAResumeRestartPlaysFromTheTop() async throws {
        engine.load(url: server.url, autoplay: true, seekTo: 50)
        await waitUntil(10) { self.engine.flacSeek.loader != nil }
        server.delay = { _ in 1 }   // the restarted stream takes a moment
        XCTAssertEqual(engine.status, .loading, "precondition: the resume's stream is still loading")
        engine.seek(to: 0)
        server.delay = { _ in 0 }
        await waitUntil(10) { self.engine.status == .playing && !self.engine.isFLACSeekInFlight }
        try await assertHeardAndShown(at: 1.5)
    }

    /// The engine's own reads of the stream (the header, the frames, the stream from mid-track) go
    /// through the session factory, so they carry the app's posture: certificate trust included.
    func testTheEnginesReadsGoThroughTheSessionFactory() async throws {
        RangeFileURLProtocol.serve(try Data(contentsOf: FLACClockFixture.url()))
        engine.clear()
        engine = makeEngine(sessions: RangeFileURLProtocol.Factory())
        engine.load(url: server.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
        engine.seek(to: 60)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        let start = try XCTUnwrap(engine.flacSeek.loader).start
        await waitUntil(10) { self.engine.status == .playing }
        let heard = try await heard()
        XCTAssertEqual(heard, 60.5, accuracy: 1.2, "landed at \(heard)")

        let reads = RangeFileURLProtocol.ranges
        XCTAssertTrue(reads.contains(0...16_383), "the header: \(reads)")
        XCTAssertTrue(reads.contains { $0.lowerBound == start.byte }, "the stream from mid-track: \(reads)")
        XCTAssertFalse(server.ranges.contains(0...16_383), "a read went around the factory: \(server.ranges)")
    }

    func testASkipWhilePausedStaysPausedAtTheTarget() async throws {
        engine.load(url: server.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
        engine.pause()
        await waitUntil(5) { self.engine.status == .paused }
        engine.seek(to: 40)
        await waitUntil(5) { !self.engine.isFLACSeekInFlight }
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(engine.status, .paused)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.currentTime, 40, accuracy: 0.25)
        XCTAssertEqual(engine.duration, 90, accuracy: 0.1)

        engine.play()
        await waitUntil(10) { self.engine.status == .playing }
        try await Task.sleep(for: .seconds(1.2))
        let heard = try await heard()
        XCTAssertEqual(heard, 41.5, accuracy: 1.2, "played on from \(heard)")
    }
}
