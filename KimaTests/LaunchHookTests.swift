import XCTest
@testable import Kima

/// The DEBUG launch hooks `SessionStore.resume()` reads from its launch arguments, proven in
/// process instead of through UI runs (ticket 30). Each test starts from a stored login (an
/// address plus an access and a refresh token for it) and checks what the hook leaves of it:
/// the first hook to match wins, and the `-kima-server` / `-kima-jwt` seeding writes before any
/// later hook runs, so order is behaviour.
@MainActor
final class LaunchHookTests: KeychainLoginTestCase {
    private let kept = KimaServer(baseURL: URL(string: "https://kept.test")!)
    private let seeded = KimaServer(baseURL: URL(string: "https://seeded.test")!)
    private let seedingArguments = ["-kima-server", "https://seeded.test", "-kima-jwt", "seeded-token"]

    override func setUpWithError() throws {
        try super.setUpWithError()   // HTTP reset, login snapshot, clean slate, hard writability assert
        ServerURLStore.setStored(kept.baseURL.absoluteString)
        XCTAssertTrue(KeychainStore.setCredential("kept-access", for: KeychainStore.accessToken, server: kept))
        XCTAssertTrue(KeychainStore.setCredential("kept-refresh", for: KeychainStore.refreshToken, server: kept))
    }

    override func quiesce() async {
        ServerURLStore.debugOverride = nil
    }

    /// A cold launch with these arguments. "Kima" stands in for argv[0], the executable path.
    private func launch(with arguments: [String]) async -> SessionStore {
        let session = SessionStore(sessions: StubSessionFactory(), launchArguments: ["Kima"] + arguments)
        await session.resume()
        return session
    }

    /// The stored login is exactly as setUp left it, and nothing was asked of a server.
    private func assertTheStoredLoginIsUntouched(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(ServerURLStore.stored, "https://kept.test", "stored address", file: file, line: line)
        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: kept), "kept-access",
                       "access token", file: file, line: line)
        XCTAssertEqual(KeychainStore.credential(KeychainStore.refreshToken, for: kept), "kept-refresh",
                       "refresh token", file: file, line: line)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "no request is sent", file: file, line: line)
    }

    /// The seeding replaced the stored login: the seeded address, its token, and no refresh token.
    private func assertTheSeededLoginIsStored(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(ServerURLStore.stored, "https://seeded.test", "stored address", file: file, line: line)
        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: seeded), "seeded-token",
                       "access token", file: file, line: line)
        XCTAssertEqual(KeychainStore.read(KeychainStore.refreshToken), .absent,
                       "no refresh token, so a 401 propagates", file: file, line: line)
    }

    func testFakeSignedOutOpensOnConnectAndKeepsTheStoredLogin() async {
        let session = await launch(with: ["-kima-fake-signed-out"])
        XCTAssertEqual(session.phase, .unauthenticated)
        XCTAssertNil(ServerURLStore.debugOverride, "signed out sets no override")
        assertTheStoredLoginIsUntouched()
    }

    /// Ticket 29's ordering bug: signed out sat after the seeding, so passing it with a server and
    /// a token still wrote a login. It runs first now, so nothing passed with it writes.
    func testFakeSignedOutWithSeedingArgumentsWritesNothing() async {
        let session = await launch(with: ["-kima-fake-signed-out"] + seedingArguments)
        XCTAssertEqual(session.phase, .unauthenticated)
        XCTAssertNil(KeychainStore.credential(KeychainStore.accessToken, for: seeded), "no token for the seeded server")
        assertTheStoredLoginIsUntouched()
    }

    func testFakeSignedOutWinsOverFakeSignedIn() async {
        let session = await launch(with: ["-kima-fake-signed-in", "-kima-fake-signed-out"])
        XCTAssertEqual(session.phase, .unauthenticated)
        XCTAssertNil(ServerURLStore.debugOverride, "signed in never ran")
        assertTheStoredLoginIsUntouched()
    }

    /// Signed in on a sink address held in this process only: written to the stored address, it
    /// would land every later launch on Connect.
    func testFakeSignedInReachesTheShellOnAProcessOnlyAddress() async {
        let session = await launch(with: ["-kima-fake-signed-in"])
        XCTAssertEqual(session.phase, .authenticated(host: "127.0.0.1:9"))
        XCTAssertEqual(ServerURLStore.debugOverride, "http://127.0.0.1:9")
        XCTAssertEqual(ServerURLStore.current, "http://127.0.0.1:9", "this process talks to the sink")
        assertTheStoredLoginIsUntouched()
    }

    /// The seeding runs before signed in, so it still writes; the session talks to the sink.
    func testFakeSignedInAfterSeedingKeepsTheSeededLogin() async {
        let session = await launch(with: seedingArguments + ["-kima-fake-signed-in"])
        XCTAssertEqual(session.phase, .authenticated(host: "127.0.0.1:9"))
        assertTheSeededLoginIsStored()
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "no request is sent")
    }

    /// Seeding alone stores the login, then resumes it like any stored login: against the seeded
    /// server, with the seeded token.
    func testSeedingStoresTheLoginAndResumesIt() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"id":"u1","username":"kima"}"#.utf8)) }
        let session = await launch(with: seedingArguments)
        XCTAssertEqual(session.phase, .authenticated(host: "seeded.test"))
        assertTheSeededLoginIsStored()
        XCTAssertEqual(StubURLProtocol.requests.map(\.url?.absoluteString), ["https://seeded.test/api/auth/me"])
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer seeded-token")
    }

    /// A seeding flag passed last has no value: it writes nothing, and the launch goes on.
    func testASeedingFlagWithNoValueWritesNothing() async {
        let session = await launch(with: ["-kima-force-unreachable", "-kima-jwt"])
        XCTAssertEqual(session.phase, .unreachable(host: "https://kept.test"))
        assertTheStoredLoginIsUntouched()
    }

    /// The unreachable gate on the stored address, without a dead server or a request.
    func testForceUnreachableGatesOnTheStoredAddress() async {
        let session = await launch(with: ["-kima-force-unreachable"])
        XCTAssertEqual(session.phase, .unreachable(host: "https://kept.test"))
        assertTheStoredLoginIsUntouched()
    }
}
