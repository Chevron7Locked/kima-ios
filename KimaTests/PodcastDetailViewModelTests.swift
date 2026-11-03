import XCTest
@testable import Kima

@MainActor
final class PodcastDetailViewModelTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset() }

    private let podcastJSON = #"{"id":"k1","title":"t","author":"a","autoDownloadEpisodes":false,"episodes":[]}"#

    private func stub() {
        let json = podcastJSON
        StubURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            switch (req.httpMethod ?? "GET", path) {
            case ("POST", "/api/podcasts/subscribe"):
                return (200, Data(#"{"success":true,"podcast":{"id":"k1","title":"t"}}"#.utf8))
            case ("GET", "/api/podcasts/k1"):
                return (200, Data(json.utf8))
            case ("DELETE", "/api/podcasts/k1/unsubscribe"):
                return (200, Data(#"{"success":true}"#.utf8))
            default:
                return (404, Data())
            }
        }
    }

    func testSubscribeFromPreviewMovesActionsToKimaId() async throws {
        stub()
        let vm = PodcastDetailViewModel(id: "itunes-123")
        _ = try await vm.subscribe(feedUrl: "https://feed.test", itunesId: "itunes-123", client: .stubbed())
        XCTAssertEqual(vm.activeId, "k1")
        try await vm.unsubscribe(client: .stubbed())
        let deletes = StubURLProtocol.requests.filter { $0.httpMethod == "DELETE" }
        XCTAssertEqual(deletes.map { $0.url?.path }, ["/api/podcasts/k1/unsubscribe"])
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url?.path.contains("itunes-123") == true })
    }

    func testLoadIfNeededSkipsWhenLoaded() async {
        stub()
        let vm = PodcastDetailViewModel(id: "k1")
        await vm.load(client: .stubbed())
        let n = StubURLProtocol.requests.count
        await vm.loadIfNeeded(client: .stubbed())
        XCTAssertEqual(StubURLProtocol.requests.count, n)
    }

    func testOldestSortPagesFromTheServer() async {
        UserDefaults.standard.set("oldest", forKey: "kima.podcast.sort.k2")
        defer { UserDefaults.standard.removeObject(forKey: "kima.podcast.sort.k2") }
        func ep(_ id: String, _ date: String) -> String {
            #"{"id":"\#(id)","title":"\#(id)","duration":1,"publishedAt":"\#(date)"}"#
        }
        let detail = #"{"id":"k2","title":"t","author":"a","autoDownloadEpisodes":false,"episodeTotal":3,"episodes":["#
            + ep("e3", "2026-03-01T00:00:00.000Z") + "]}"
        let oldestPage = #"{"episodes":["# + ep("e1", "2026-01-01T00:00:00.000Z") + ","
            + ep("e2", "2026-02-01T00:00:00.000Z") + #"],"total":3}"#
        StubURLProtocol.handler = { req in
            switch req.url?.path ?? "" {
            case "/api/podcasts/k2": return (200, Data(detail.utf8))
            case "/api/podcasts/k2/episodes": return (200, Data(oldestPage.utf8))
            default: return (404, Data())
            }
        }
        let vm = PodcastDetailViewModel(id: "k2")
        await vm.load(client: .stubbed())
        guard case .subscribed = vm.mode else { return XCTFail("expected subscribed") }

        let pageRequest = StubURLProtocol.requests.first { $0.url?.path == "/api/podcasts/k2/episodes" }
        XCTAssertTrue(pageRequest?.url?.query?.contains("order=oldest") == true)
        XCTAssertEqual(vm.sortedEpisodes().map(\.id), ["e1", "e2"])
        XCTAssertTrue(vm.canLoadMore)

        vm.episodeSort = .newest
        XCTAssertEqual(vm.sortedEpisodes().map(\.id), ["e3"])
    }
}
