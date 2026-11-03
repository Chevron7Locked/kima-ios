import XCTest
@testable import Kima

/// Whether download controls show: a server that does not send `canAcquire` (older than the operator-only rule) does
/// not restrict downloads, and an answer the app cannot read changes nothing and is asked again.
@MainActor
final class AcquirePermissionTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset() }

    private func answer(_ status: Int, _ body: String) {
        StubURLProtocol.handler = { _ in (status, Data(body.utf8)) }
    }

    func testDecodesWithAndWithoutTheField() throws {
        let old = try JSONDecoder().decode(PublicConfig.self, from: Data(#"{"publicUrl":null}"#.utf8))
        XCTAssertTrue(old.canAcquire)
        let locked = try JSONDecoder().decode(PublicConfig.self, from: Data(#"{"publicUrl":"x","canAcquire":false}"#.utf8))
        XCTAssertFalse(locked.canAcquire)
    }

    func testAServerWithoutTheFieldAllowsDownloads() async {
        answer(200, #"{"publicUrl":null}"#)
        let permission = AcquirePermission()
        await permission.refresh(client: .stubbed())
        XCTAssertTrue(permission.canAcquire)
        XCTAssertFalse(permission.isLocked)
    }

    func testAServerWithoutTheRouteAllowsDownloads() async {
        answer(404, #"{"error":"Not found"}"#)
        let permission = AcquirePermission()
        await permission.refresh(client: .stubbed())
        XCTAssertTrue(permission.canAcquire)
    }

    func testAnUnreadableAnswerLocksNothingAndIsAskedAgain() async {
        answer(200, #"{"canAcquire":"yes"}"#)
        let permission = AcquirePermission()
        await permission.refresh(client: .stubbed())
        XCTAssertFalse(permission.isLocked, "an answer the app can't read is not a refusal")
        answer(200, #"{"publicUrl":null,"canAcquire":true}"#)
        await permission.refresh(client: .stubbed())
        XCTAssertTrue(permission.canAcquire, "the next refresh asks again")
    }

    func testARefusalLocks() async {
        answer(200, #"{"publicUrl":null,"canAcquire":false}"#)
        let permission = AcquirePermission()
        await permission.refresh(client: .stubbed())
        XCTAssertFalse(permission.canAcquire)
        XCTAssertTrue(permission.isLocked)
    }
}
