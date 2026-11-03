import XCTest
@testable import Kima

@MainActor
final class SettingsViewModelTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testDeleteAccountRetriesConcurrentChange() async throws {
        StubURLProtocol.handler = { _ in
            if StubURLProtocol.requests.count == 1 {
                return (409, Data(#"{"error":"Concurrent account change, please retry"}"#.utf8))
            }
            return (200, Data(#"{"deleted":true}"#.utf8))
        }
        try await SettingsViewModel().deleteAccount(client: .stubbed())
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func testDeleteAccountLastAdminDoesNotRetry() async {
        StubURLProtocol.handler = { _ in
            (409, Data(#"{"error":"Cannot delete the only administrator account"}"#.utf8))
        }
        do {
            try await SettingsViewModel().deleteAccount(client: .stubbed())
            XCTFail("expected a throw")
        } catch APIError.http(let status, _) {
            XCTAssertEqual(status, 409)
        } catch {
            XCTFail("wrong error: \(error)")
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }
}
