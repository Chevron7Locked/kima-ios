import XCTest
@testable import Kima

@MainActor
final class ReleasesViewModelTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset() }

    func testFailedRefetchKeepsPreviousReleases() async {
        let body = #"{"upcoming":[],"recent":[],"monitoredArtistCount":3,"similarArtistCount":1}"#
        StubURLProtocol.handler = { _ in (200, Data(body.utf8)) }
        let vm = ReleasesViewModel()
        let client = KimaAPIClient.stubbed()
        let first = await vm.load(using: client)
        XCTAssertTrue(first)
        guard case .loaded = vm.phase else { return XCTFail("expected loaded") }

        StubURLProtocol.handler = { _ in (500, Data()) }
        let second = await vm.load(using: client)
        XCTAssertFalse(second)
        guard case .loaded(let r) = vm.phase else { return XCTFail("feed was blanked") }
        XCTAssertEqual(r.monitoredArtistCount, 3)
    }

    func testFirstLoadFailureShowsFailed() async {
        StubURLProtocol.handler = { _ in (500, Data()) }
        let vm = ReleasesViewModel()
        _ = await vm.load(using: KimaAPIClient.stubbed())
        guard case .failed = vm.phase else { return XCTFail("expected failed") }
    }
}
