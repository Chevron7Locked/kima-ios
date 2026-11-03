import XCTest
@testable import Kima

/// The what's-new gate asks the server once per signed-in session; a failed ask is retried.
@MainActor
final class WhatsNewGateModelTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset() }

    private var pendingRequests: Int {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/whats-new/pending") == true }.count
    }

    func testLoadsOnceAfterSuccess() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"releases":[]}"#.utf8)) }
        let gate = WhatsNewGateModel(client: .stubbed())
        await gate.loadOnce()
        await gate.loadOnce()
        XCTAssertEqual(pendingRequests, 1)
    }

    func testFailedLoadIsRetried() async {
        StubURLProtocol.handler = { _ in (500, Data()) }
        let gate = WhatsNewGateModel(client: .stubbed())
        await gate.loadOnce()
        StubURLProtocol.handler = { _ in (200, Data(#"{"releases":[]}"#.utf8)) }
        await gate.loadOnce()
        await gate.loadOnce()
        XCTAssertEqual(pendingRequests, 2)
    }
}
