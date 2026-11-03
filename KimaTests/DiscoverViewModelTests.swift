import XCTest
@testable import Kima

@MainActor
final class DiscoverViewModelTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset() }

    private let weekly = #"{"weekStart":"2026-10-05","weekEnd":"2026-10-11","tracks":[],"unavailable":[],"totalCount":0,"unavailableCount":0}"#
    private let idle = #"{"active":false}"#

    func testFailedRefreshKeepsLoadedFeed() async {
        StubURLProtocol.handler = { [weekly, idle] req in
            (200, Data((req.url?.path.hasSuffix("batch-status") == true ? idle : weekly).utf8))
        }
        let vm = DiscoverViewModel()
        let client = KimaAPIClient.stubbed()
        await vm.load(using: client)
        guard case .loaded = vm.playlistPhase else { return XCTFail("expected loaded") }

        StubURLProtocol.handler = { _ in (500, Data()) }
        await vm.load(using: client)
        guard case .loaded(let p) = vm.playlistPhase else { return XCTFail("feed was blanked") }
        XCTAssertEqual(p.weekStart, "2026-10-05")
    }

    func testFirstLoadFailureShowsFailed() async {
        StubURLProtocol.handler = { _ in (500, Data()) }
        let vm = DiscoverViewModel()
        await vm.load(using: KimaAPIClient.stubbed())
        guard case .failed = vm.playlistPhase else { return XCTFail("expected failed") }
    }

    func testBuildPastTheTimeoutRefetchesAndSaysSo() async throws {
        let active = #"{"active":true,"status":"downloading"}"#
        StubURLProtocol.handler = { [weekly] req in
            (200, Data((req.url?.path.hasSuffix("batch-status") == true ? active : weekly).utf8))
        }
        let vm = DiscoverViewModel(pollInterval: .milliseconds(50), pollTimeout: 0.1)
        let client = KimaAPIClient.stubbed()
        await vm.load(using: client)
        XCTAssertTrue(vm.isGenerating)
        let fetchesBefore = StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/discover/current") == true }.count

        try await Task.sleep(for: .milliseconds(600))
        XCTAssertFalse(vm.isGenerating)
        XCTAssertTrue(vm.stoppedWatchingBuild)
        let fetchesAfter = StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/discover/current") == true }.count
        XCTAssertGreaterThan(fetchesAfter, fetchesBefore)
        vm.stopPolling()
    }

    func testReloadThatFindsNoBuildEndsBuilding() async {
        let active = #"{"active":true,"status":"downloading"}"#
        StubURLProtocol.handler = { [weekly] req in
            (200, Data((req.url?.path.hasSuffix("batch-status") == true ? active : weekly).utf8))
        }
        let vm = DiscoverViewModel(pollInterval: .seconds(60))
        let client = KimaAPIClient.stubbed()
        await vm.load(using: client)
        XCTAssertTrue(vm.isGenerating)

        StubURLProtocol.handler = { [weekly, idle] req in
            (200, Data((req.url?.path.hasSuffix("batch-status") == true ? idle : weekly).utf8))
        }
        await vm.load(using: client)   // what a live discover:complete event triggers
        XCTAssertFalse(vm.isGenerating)
    }
}
