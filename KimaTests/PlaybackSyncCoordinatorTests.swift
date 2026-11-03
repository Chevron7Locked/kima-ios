import XCTest
@testable import Kima

/// Queue sync with the server: no polling while a queue is loaded, and saves that reach the
/// server one at a time in the order they were made.
@MainActor
final class PlaybackSyncCoordinatorTests: XCTestCase {

    override func tearDown() { StubURLProtocol.reset() }

    private func controller(queued ids: [String]) throws -> PlaybackController {
        let c = PlaybackController(server: KimaServer(baseURL: URL(string: "https://stub.test")!))
        c.queue = try ids.map(Track.fixture)
        return c
    }

    private func gets() -> Int {
        StubURLProtocol.requests.filter { $0.httpMethod == "GET" && $0.url?.path.hasSuffix("/playback-state") == true }.count
    }

    func testNoPollingWhileAQueueIsLoaded() async throws {
        StubURLProtocol.handler = { _ in (200, Data("null".utf8)) }
        let c = try controller(queued: ["a"])
        let sync = PlaybackSyncCoordinator(controller: c, client: .stubbed())
        sync.pollInterval = .milliseconds(50)
        sync.start()
        try await Task.sleep(for: .milliseconds(450))
        sync.stop()
        XCTAssertEqual(gets(), 1, "only the launch fetch; a loaded queue is never replaced")
    }

    func testPollingWhileNothingIsLoaded() async throws {
        StubURLProtocol.handler = { _ in (200, Data("null".utf8)) }
        let c = try controller(queued: [])
        let sync = PlaybackSyncCoordinator(controller: c, client: .stubbed())
        sync.pollInterval = .milliseconds(50)
        sync.start()
        try await Task.sleep(for: .milliseconds(450))
        sync.stop()
        XCTAssertGreaterThan(gets(), 2)
    }

    func testAnOlderSaveCannotLandAfterANewerOne() async throws {
        nonisolated(unsafe) var spans: [(start: Date, end: Date)] = []
        StubURLProtocol.handler = { req in
            let start = Date()
            // The first save is slow; a newer one must wait for it instead of overtaking it.
            if spans.isEmpty { Thread.sleep(forTimeInterval: 0.4) }
            spans.append((start, Date()))
            return (200, Data(#"{"playbackType":"track","currentIndex":0,"isShuffle":false}"#.utf8))
        }
        let c = try controller(queued: ["a", "b"])
        let sync = PlaybackSyncCoordinator(controller: c, client: .stubbed())
        sync.saveDelay = .milliseconds(10)
        sync.scheduleStateSave()
        try await Task.sleep(for: .milliseconds(150))   // the first POST is on the wire
        c.currentIndex = 1
        sync.scheduleStateSave()
        try await Task.sleep(for: .milliseconds(900))
        let saves = StubURLProtocol.posts(to: "/playback-state")
        XCTAssertEqual(saves.map { $0["currentIndex"] as? Int }, [0, 1])
        XCTAssertEqual(spans.count, 2)
        if spans.count == 2 {
            XCTAssertGreaterThanOrEqual(spans[1].start, spans[0].end, "the newer save waited for the older one")
        }
    }

    func testSavesInAQuickRowSendOnlyTheNewest() async throws {
        StubURLProtocol.handler = { _ in (200, Data(#"{"playbackType":"track","currentIndex":0,"isShuffle":false}"#.utf8)) }
        let c = try controller(queued: ["a", "b", "c"])
        let sync = PlaybackSyncCoordinator(controller: c, client: .stubbed())
        sync.saveDelay = .milliseconds(50)
        for i in 0..<3 {
            c.currentIndex = i
            sync.scheduleStateSave()
        }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(StubURLProtocol.posts(to: "/playback-state").map { $0["currentIndex"] as? Int }, [2])
    }
}
