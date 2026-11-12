import XCTest
@testable import Kima

/// The launch resume decision — authenticated / needs sign-in / unreachable — classified through
/// the session-factory seam: a stub adapter answers `/auth/me` (or refuses the connection), so
/// each branch is proven by what it sends and keeps, not by DNS tricks or environment-dependent
/// skips. On-device behavior these pin: a revoked server still signs the user out at launch; an
/// offline launch offers retry rather than silent sign-out.
@MainActor
final class LaunchResumeTests: XCTestCase {
    private let server = KimaServer(baseURL: URL(string: "https://resume.test")!)
    private var savedLogin = KeychainLoginSnapshot()

    override func setUpWithError() throws {
        StubURLProtocol.reset()
        savedLogin = KeychainLoginSnapshot()
        // These tests must run and pass, not skip: a host that cannot write the Keychain is an
        // environment failure worth going red over.
        XCTAssertTrue(KeychainStore.setCredential("probe", for: KeychainStore.accessToken, server: server))
        XCTAssertTrue(KeychainStore.clearCredentials())
        UserDefaults.standard.set(server.baseURL.absoluteString, forKey: ServerURLStore.key)
        XCTAssertTrue(KeychainStore.setCredential("live-token", for: KeychainStore.accessToken, server: server))
        // No refresh token is stored: a 401 propagates instead of looping (the -kima-jwt rule).
    }

    override func tearDown() {
        StubURLProtocol.reset()
        savedLogin.restore()   // takes the stored server address back with it
    }

    private func respond(_ status: Int, _ body: String = "{}") {
        StubURLProtocol.handler = { _ in (status, Data(body.utf8)) }
    }

    func testResumeWithLiveSessionLandsAuthenticated() async {
        respond(200, #"{"id":"u1","username":"kima"}"#)
        let session = SessionStore(sessions: StubSessionFactory())
        await session.resume()
        XCTAssertEqual(session.phase, .authenticated(host: "resume.test"))
        XCTAssertEqual(StubURLProtocol.requests.map(\.url?.path), ["/api/auth/me"])
    }

    func testResumeWithRevokedLoginFallsBackToSignIn() async {
        // The 401 interceptor already tried a refresh in send(); with no refresh token stored the
        // 401 arrives here as "both credentials are dead": wipe them and show Connect.
        respond(401)
        let session = SessionStore(sessions: StubSessionFactory())
        await session.resume()
        XCTAssertEqual(session.phase, .unauthenticated)
        XCTAssertEqual(KeychainStore.read(KeychainStore.accessToken), .absent, "dead tokens are wiped")
    }

    func testResumeWithFailingServerGatesWithTheReason() async {
        // The server answered, but not with the account: every screen would fail, so the same
        // gate offers retry and a new address, carrying why.
        respond(500, #"{"error":"boom"}"#)
        let session = SessionStore(sessions: StubSessionFactory())
        await session.resume()
        XCTAssertEqual(session.phase, .unreachable(host: "resume.test",
                                                   serverError: "the server returned an error (500)."))
    }

    func testResumeWithoutACredentialSendsNothing() async {
        XCTAssertTrue(KeychainStore.clearCredentials())
        let session = SessionStore(sessions: StubSessionFactory())
        await session.resume()
        XCTAssertEqual(session.phase, .unauthenticated)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "Connect appears before any request")
    }

    func testResumeWithoutAStoredServerSendsNothing() async {
        UserDefaults.standard.removeObject(forKey: ServerURLStore.key)
        let session = SessionStore(sessions: StubSessionFactory())
        await session.resume()
        XCTAssertEqual(session.phase, .unauthenticated)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testOfflineLaunchOffersRetryWithoutSigningOut() async {
        // No HTTP answer at all — offline, DNS, TLS, a moved address. The gate (Retry / Change
        // server) must appear and the login must survive: a blip recovers with one tap.
        let session = SessionStore(sessions: StubSessionFactory(protocolClasses: [FailingURLProtocol.self]))
        await session.resume()
        XCTAssertEqual(session.phase, .unreachable(host: "resume.test"))
        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: server), "live-token",
                       "offline is not a sign-out")
    }
}
