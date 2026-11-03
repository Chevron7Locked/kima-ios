import XCTest
@testable import Kima

/// A mood tile's preview is read without starting a listening session on the server, and a refresh keeps the
/// tiles' previews on screen until the new ones arrive.
@MainActor
final class RadioPreviewTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset() }

    private let station = RadioStation(id: "mood-chill", name: "Chill", description: "d", filterType: "mood",
                                       filterValue: "chill", minTracks: 1)

    private func radioRequests() -> [URLRequest] {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/library/radio") == true }
    }

    private func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    private func stub() {
        StubURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("/library/radio") == true {
                return (200, Data(#"{"tracks":[{"id":"t1","title":"t","duration":1}]}"#.utf8))
            }
            return (500, Data())
        }
    }

    func testPreviewSendsNoSeedSoTheServerKeepsNoSession() async throws {
        stub()
        let vm = RadioViewModel()
        await vm.loadPreview(station, using: .stubbed())
        let request = try XCTUnwrap(radioRequests().first)
        XCTAssertNil(query(request)["seed"], "a seed makes the server save the preview as the listener's station")
        XCTAssertNil(query(request)["offset"])
        XCTAssertTrue(vm.previews["chill"]?.isLoaded == true)
    }

    func testRefreshKeepsPreviewsAndTheTilesAskAgain() async throws {
        stub()
        let vm = RadioViewModel()
        let client = KimaAPIClient.stubbed()
        await vm.loadPreview(station, using: client)
        await vm.refresh(using: client)
        XCTAssertTrue(vm.previews["chill"]?.isLoaded == true, "the tile keeps its covers until new ones arrive")
        await vm.loadPreview(station, using: client)
        XCTAssertEqual(radioRequests().count, 2, "after a refresh the tile asks again")
        await vm.loadPreview(station, using: client)
        XCTAssertEqual(radioRequests().count, 2, "and only once per refresh")
    }
}
