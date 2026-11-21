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
        server = RangeFileServer(data: try Data(contentsOf: FLACClockFixture.url()))
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
        RangeFileServer(data: try Data(contentsOf: FLACClockFixture.url(ext: "wav")), mime: "audio/wav")
    }
}
