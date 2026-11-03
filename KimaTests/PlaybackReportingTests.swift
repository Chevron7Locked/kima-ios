import MediaPlayer
import XCTest
@testable import Kima

/// Play reports that don't get through, a stream warm-up that finishes after the player moved on, and
/// lock-screen command answers.
@MainActor
final class PlaybackReportingTests: XCTestCase {

    override func tearDown() { StubURLProtocol.reset() }

    private func controller() -> PlaybackController {
        .stubbed()
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(400)) }

    // MARK: Play reports

    func testAPlayReportThatFailsIsSentOnceMore() async throws {
        var calls = 0
        StubURLProtocol.handler = { _ in
            calls += 1
            return calls == 1 ? (503, Data()) : (200, Data(#"{"recorded":true}"#.utf8))
        }
        let c = controller()
        c.playReportRetryDelay = .milliseconds(50)
        c.sendPlayReport(client: .stubbed(), trackId: "a", seconds: 120)
        try await settle()
        let reports = StubURLProtocol.posts(to: "/plays")
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports.last?["trackId"] as? String, "a")
        XCTAssertEqual(reports.last?["secondsListened"] as? Int, 120)
    }

    func testAPlayReportIsRetriedOnlyOnce() async throws {
        StubURLProtocol.handler = { _ in (503, Data()) }
        let c = controller()
        c.playReportRetryDelay = .milliseconds(50)
        c.sendPlayReport(client: .stubbed(), trackId: "a", seconds: 120)
        try await settle()
        XCTAssertEqual(StubURLProtocol.posts(to: "/plays").count, 2)
    }

    func testARefusedPlayReportIsNotRetried() async throws {
        StubURLProtocol.handler = { _ in (404, Data()) }
        let c = controller()
        c.playReportRetryDelay = .milliseconds(50)
        c.sendPlayReport(client: .stubbed(), trackId: "gone", seconds: 120)
        try await settle()
        XCTAssertEqual(StubURLProtocol.posts(to: "/plays").count, 1, "the server's answer won't change")
    }

    // MARK: Prefetch

    private func queuedController() throws -> PlaybackController {
        StubURLProtocol.handler = { _ in
            Thread.sleep(forTimeInterval: 0.2)   // a slow ticket
            return (200, Data(#"{"ticket":"t","expiresIn":3600}"#.utf8))
        }
        let c = controller()
        c.apiClient = .stubbed()
        c.queue = try ["a", "b"].map(Track.fixture)
        return c
    }

    func testAWarmUpThatFinishesAfterAStopIsDropped() async throws {
        let c = try queuedController()
        c.prefetchNextStream()
        c.engine.clear()   // stopped (or signed out) while the ticket was on its way
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(c.engine.prefetchedAsset, "a cleared stream URL must not come back")
    }

    func testAWarmUpLandsWhenNothingChanged() async throws {
        let c = try queuedController()
        c.prefetchNextStream()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(c.engine.prefetchedAsset?.url.path, "/api/library/tracks/b/stream")
    }

    // MARK: Remote commands

    func testRemoteCommandAnswersComeFromTheMainActorOnAnyThread() async {
        let offMain = await Task.detached {
            NowPlayingController.onMain {
                MainActor.assertIsolated()
                return .noActionableNowPlayingItem
            }
        }.value
        XCTAssertEqual(offMain, .noActionableNowPlayingItem)
        XCTAssertEqual(NowPlayingController.onMain { .success }, .success)
    }
}
