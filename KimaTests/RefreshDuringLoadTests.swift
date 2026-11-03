import XCTest
@testable import Kima

@MainActor
final class RefreshDuringLoadTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset() }

    func testPlaylistsPullDuringLoadWaitsForTheRunningLoad() async {
        StubURLProtocol.handler = { _ in
            Thread.sleep(forTimeInterval: 0.3)   // keep the first load running while the pull arrives
            return (200, Data("[]".utf8))
        }
        let vm = PlaylistsListViewModel()
        let client = KimaAPIClient.stubbed()
        async let first: Void = vm.load(using: client)
        async let pull: Void = vm.load(using: client)
        _ = await (first, pull)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertFalse(vm.isLoading)

        await vm.load(using: client)   // a later pull runs its own load
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }
}
