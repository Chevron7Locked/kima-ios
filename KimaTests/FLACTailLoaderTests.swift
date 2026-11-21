import AVFoundation
import XCTest
@testable import Kima

/// A FLAC served from mid-track: found by range reads over HTTP, played from a synthesized header
/// plus the original frames. What's heard must be the frame the finder said it starts at.
@MainActor
final class FLACTailLoaderTests: XCTestCase {
    private var server: RangeFileServer!

    override func setUp() async throws {
        server = RangeFileServer(data: try Data(contentsOf: FLACClockFixture.url()))
        try server.start()
    }

    override func tearDown() async throws { server.stop() }

    func testFinderLandsWithinAQuarterSecondBeforeTheTarget() async throws {
        let source = FLACByteSource.http(server.url, session: ProductionSessionFactory().makeSession())
        let read = try await FLACStream.read(from: source)
        let stream = try XCTUnwrap(read)
        for target in [0.0, 1.0, 37.3, 60.0, 89.5] {
            let found = try await stream.start(at: target, from: source)
            let start = try XCTUnwrap(found)
            let at = Double(start.sample) / FLACClockFixture.sampleRate
            XCTAssertLessThanOrEqual(at, target + 0.0001, "start for \(target)")
            XCTAssertGreaterThan(at, target - 0.25, "start for \(target)")
        }
    }

    func testATailPlaysFromTheFrameItStartsAt() async throws {
        let source = FLACByteSource.http(server.url, session: ProductionSessionFactory().makeSession())
        let read = try await FLACStream.read(from: source)
        let stream = try XCTUnwrap(read)
        let found = try await stream.start(at: 60, from: source)
        let start = try XCTUnwrap(found)
        let loader = FLACTailLoader(source: server.url, stream: stream, start: start, session: ProductionSessionFactory().makeSession())
        let item = AVPlayerItem(asset: loader.makeAsset())
        let tap = ClockTap()
        try await tap.attach(to: item)
        let player = AVPlayer(playerItem: item)
        player.volume = 0
        player.play()
        await waitUntil(10) { tap.heardSeconds.map { $0 > 0.5 } == true }

        let heard = try XCTUnwrap(tap.heardSeconds, "no audio reached the tap")
        let played = player.currentTime().seconds
        let startsAt = Double(start.sample) / FLACClockFixture.sampleRate
        XCTAssertEqual(heard, startsAt + played, accuracy: 0.5, "heard \(heard), start \(startsAt) + played \(played)")
        XCTAssertEqual(item.duration.seconds, 90 - startsAt, accuracy: 0.1)
        player.pause()
        withExtendedLifetime(loader) {}
    }
}
