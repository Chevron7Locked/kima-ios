import AVFoundation
import XCTest
@testable import Kima

/// The harness for tests that listen to the engine's audio: a real engine playing the
/// self-timestamping fixture (`FLACClockFixture`) silently from an in-process range server, and a
/// tap that reads the position heard off the audio itself.
@MainActor
class FLACClockTestCase: XCTestCase {
    var server: RangeFileServer!
    var engine: PlaybackEngine!

    override func setUp() async throws {
        server = RangeFileServer(data: try FLACClockFixture.data())
        try server.start()
        engine = makeEngine()
    }

    override func tearDown() async throws {
        engine.clear()
        server.stop()
    }

    /// An engine that never touches the host's audio session and plays silently.
    func makeEngine(sessions: any SessionFactory = .production) -> PlaybackEngine {
        let engine = PlaybackEngine(sessions: sessions)
        engine.activateSession = { _ in }
        engine.player.volume = 0
        return engine
    }

    /// How long a stopped engine is watched for starting anyway after its item is ready: the late
    /// KVO a swap leaves (waiting, then ready) hops to the main actor a turn or two later. Not a
    /// measured bound: 500 ms caught the wrong start every run while it was a bug (2026-11-20).
    static let settle = Duration.milliseconds(500)

    /// Once the current item is ready, the engine stays silent through `settle`: no rate, not shown
    /// playing. `step` names what would have started it, for the failure message.
    func assertStaysSilentOnceReady(after step: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        await waitUntil(10) { self.engine.player.currentItem?.status == .readyToPlay }
        XCTAssertEqual(engine.player.currentItem?.status, .readyToPlay, "precondition: the item got ready", file: file, line: line)
        try await Task.sleep(for: Self.settle)
        XCTAssertEqual(engine.player.rate, 0, "playback started after \(step)", file: file, line: line)
        XCTAssertFalse(engine.isPlaying, "shown playing after \(step)", file: file, line: line)
    }

    /// The engine playing the fixture (or `url`) from the top.
    func playing(_ url: URL? = nil) async {
        engine.load(url: url ?? server.url, autoplay: true)
        await waitUntil(10) { self.engine.status == .playing }
    }

    /// Shown play/pause flips (`onPlaybackStateChanged`) from now on.
    func countStateChanges() -> () -> Int {
        var changes = 0
        engine.onPlaybackStateChanged = { changes += 1 }
        return { changes }
    }

    /// A call comes in: the OS pauses the player, then tells the engine.
    func beginInterruption() {
        engine.player.pause()
        engine.handleInterruption(.began, shouldResume: false)
    }

    /// Skips to `seconds` and waits until the skip's stream is in (a FLAC skip swaps the item).
    func skipSwapped(to seconds: Double, file: StaticString = #filePath, line: UInt = #line) async {
        engine.seek(to: seconds)
        await waitUntil(5) { self.engine.isRestartedStream && !self.engine.isFLACSeekInFlight }
        XCTAssertTrue(engine.isRestartedStream, "precondition: the skip swapped the item", file: file, line: line)
    }

    /// The position heard right now, read off the audio.
    func heard() async throws -> Double {
        let tap = ClockTap()
        try await tap.attach(to: XCTUnwrap(engine.player.currentItem))
        // A tap attached mid-play is primed with silence (index 0) before the item's audio reaches it.
        await waitUntil(5) { (tap.heardSeconds ?? 0) > 0.5 }
        return try XCTUnwrap(tap.heardSeconds, "no audio reached the tap")
    }

    /// After 1.2 s more play, the sound is at `expected` (where it started, plus that), and the
    /// clock shows it. The tap reads a little ahead of the output; the 1 Hz clock trails by up to 1 s.
    func assertHeardAndShown(at expected: Double, file: StaticString = #filePath, line: UInt = #line) async throws {
        try await Task.sleep(for: .seconds(1.2))
        let heard = try await heard()
        XCTAssertEqual(heard, expected, accuracy: 1.2, "playing at \(heard)", file: file, line: line)
        XCTAssertEqual(engine.currentTime, heard, accuracy: 1.3, "shown \(engine.currentTime)", file: file, line: line)
    }

    /// The fixture as WAV: a format the engine never restarts.
    func wavServer() throws -> RangeFileServer {
        RangeFileServer(data: try FLACClockFixture.data(ext: "wav"), mime: "audio/wav")
    }
}
