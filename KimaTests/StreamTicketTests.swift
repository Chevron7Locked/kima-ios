import XCTest
@testable import Kima

/// The login token may reach a stream URL only when the server has no ticket endpoint (404).
final class StreamTicketTests: XCTestCase {
    override func setUp() { StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset() }

    /// A session whose every request fails at the transport level (no HTTP response at all).
    private final class FailingProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
        override func stopLoading() {}
    }

    private let jwt = "SECRET.LOGIN.JWT"

    /// Runs `body` with the Keychain access token set to a known value, saved for `server` (the
    /// stub server unless given), then restores it.
    private func withKnownLoginToken(server: String = "https://stub.test", _ body: () async throws -> Void) async rethrows {
        let login = KeychainLoginSnapshot()
        defer { login.restore() }
        let owner = KimaServer(baseURL: URL(string: server)!)
        XCTAssertTrue(KeychainStore.setCredential(jwt, for: KeychainStore.accessToken, server: owner))
        try await body()
    }

    /// The stream URLs a caller could build from `token` (none when there is no token).
    private func streamURLs(from token: String?) -> [URL] {
        guard let token else { return [] }
        let server = KimaServer(baseURL: URL(string: "https://stub.test")!)
        return [StreamURL.track(base: server, trackId: "t1", token: token)].compactMap { $0 }
    }

    func testTicket200GivesTheTicketNotTheJwt() async {
        await withKnownLoginToken {
            StubURLProtocol.handler = { _ in (200, Data(#"{"ticket":"t1","expiresIn":3600}"#.utf8)) }
            let token = await KimaAPIClient.stubbed(credential: .jwt(jwt)).streamTicket()
            XCTAssertEqual(token, "t1")
            let urls = streamURLs(from: token)
            XCTAssertEqual(urls.count, 1)
            XCTAssertTrue(urls[0].absoluteString.contains("t1"))
            XCTAssertFalse(urls[0].absoluteString.contains(jwt))
        }
    }

    func testTicket404FallsBackToTheLoginToken() async {
        await withKnownLoginToken {
            StubURLProtocol.handler = { _ in (404, Data()) }
            let token = await KimaAPIClient.stubbed(credential: .jwt(jwt)).streamTicket()
            XCTAssertEqual(token, jwt)
            XCTAssertEqual(streamURLs(from: token).count, 1)
        }
    }

    func testTicket404NeverFallsBackToAnotherServersToken() async {
        await withKnownLoginToken(server: "https://other.test") {
            StubURLProtocol.handler = { _ in (404, Data()) }
            let token = await KimaAPIClient.stubbed(credential: .jwt(jwt)).streamTicket()
            XCTAssertNil(token)
        }
    }

    func testTicket500And503ProduceNoToken() async {
        for status in [500, 503] {
            await withKnownLoginToken {
                StubURLProtocol.handler = { _ in (status, Data()) }
                let token = await KimaAPIClient.stubbed(credential: .jwt(jwt)).streamTicket()
                XCTAssertNil(token, "status \(status)")
                XCTAssertTrue(streamURLs(from: token).isEmpty)
            }
        }
    }

    func testTicket401ProducesNoToken() async {
        // API-key credential: a 401 comes back as-is, without the refresh round-trip that would
        // touch the stored session tokens.
        await withKnownLoginToken {
            StubURLProtocol.handler = { _ in (401, Data()) }
            let token = await KimaAPIClient.stubbed(credential: .apiKey("k")).streamTicket()
            XCTAssertNil(token)
            XCTAssertTrue(streamURLs(from: token).isEmpty)
        }
    }

    func testNetworkErrorProducesNoToken() async {
        await withKnownLoginToken {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [FailingProtocol.self]
            let client = KimaAPIClient(server: KimaServer(baseURL: URL(string: "https://stub.test")!),
                                       credential: .jwt(jwt), session: URLSession(configuration: config))
            let token = await client.streamTicket()
            XCTAssertNil(token)
            XCTAssertTrue(streamURLs(from: token).isEmpty)
        }
    }

    func testMalformed200ProducesNoToken() async {
        await withKnownLoginToken {
            StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
            let token = await KimaAPIClient.stubbed(credential: .jwt(jwt)).streamTicket()
            XCTAssertNil(token)
        }
    }
}
