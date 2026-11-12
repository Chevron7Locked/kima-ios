import XCTest
@testable import Kima

/// The session-factory seam (ticket 08): one module hands out every URLSession the app uses, and
/// two real adapters make it honest — production attaches the certificate trust delegate, and so
/// does the test stub, so unit tests exercise the trust layer they ship behind instead of routing
/// around it. Seam: `SessionFactory.makeSession` on each adapter; consumers are covered by their
/// own suites riding the injected factory.
final class SessionFactoryTests: XCTestCase {

    /// The headline ruling: a session from the production adapter carries the TOFU delegate.
    /// Before the factory, this was true only because each consumer remembered to attach it.
    func testProductionAdapterAttachesTheTrustDelegate() {
        let session = ProductionSessionFactory().makeSession()
        XCTAssertTrue(session.delegate === ServerTrustCoordinator.shared,
                      "every handed-out session must run the certificate story")
    }

    /// The privacy posture every consumer shared by hand before the factory: ephemeral, so
    /// authenticated responses and cookies never persist to disk readable without the JWT.
    /// (Ephemeral sessions do vend a cache — memory-only, zero disk — and an unshared cookie
    /// storage that dies with the process; those are the observable halves of "never persists".)
    func testHandedOutSessionsAreEphemeral() {
        let config = ProductionSessionFactory().makeSession().configuration
        XCTAssertEqual(config.urlCache?.diskCapacity, 0, "authenticated responses must never reach a disk cache")
        XCTAssertFalse(config.httpCookieStorage === HTTPCookieStorage.shared,
                       "cookies must not ride the persistent shared storage")
    }

    /// Where a consumer genuinely differs — the event stream's finite timeouts — reaches the
    /// configuration it ships on.
    func testPerUseOverridesReachTheConfiguration() {
        let session = ProductionSessionFactory().makeSession(
            SessionNeeds(requestTimeout: 600, resourceTimeout: 86_400))
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 600)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 86_400)
    }

    /// No overrides means the system defaults survive untouched — Foundation documents
    /// `timeoutIntervalForRequest` as 60s.
    func testNoOverridesKeepTheSystemDefaults() {
        let session = ProductionSessionFactory().makeSession(.init())
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 60)
    }

    /// The other half of "two real adapters": the test stub keeps the trust delegate too, so the
    /// suites riding it exercise the certificate layer they ship behind instead of a bare session.
    func testStubAdapterKeepsTheTrustDelegate() {
        let session = StubSessionFactory().makeSession()
        XCTAssertTrue(session.delegate === ServerTrustCoordinator.shared,
                      "the stub must run the same trust posture as production")
    }

    /// And it answers through the stub: canned responses on the shared posture.
    func testStubAdapterAnswersThroughTheStub() async throws {
        StubURLProtocol.reset()
        addTeardownBlock { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (200, Data(#"{"ok":true}"#.utf8)) }

        let (data, response) = try await StubSessionFactory().makeSession()
            .data(from: URL(string: "https://stub.test/ping")!)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"ok":true}"#)
    }

    /// The hole the factory closes under test: a stubbed client's long-timeout calls ride the
    /// stub too — that session used to be minted privately, outside every injection.
    func testStubbedClientRoutesLongTimeoutCallsThroughTheStub() async throws {
        StubURLProtocol.reset()
        addTeardownBlock { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }

        struct Body: Encodable { let query: String }
        _ = try await KimaAPIClient.stubbed()
            .postJSONLongTimeout("/long", body: Body(query: "x"), authed: true) as [String: String]

        XCTAssertTrue(StubURLProtocol.requests.contains { $0.url?.path.hasSuffix("/long") == true },
                      "the long-timeout session must come from the injected factory, not a private one")
    }
}
