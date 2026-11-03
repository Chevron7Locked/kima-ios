import XCTest
@testable import Kima

/// The one request path in `KimaAPIClient`: auth header, 401 → refresh → retry once, status mapping.
final class KimaAPIClientTests: XCTestCase {
    private struct Item: Codable, Equatable { let id: Int }
    private struct Body: Encodable { let name: String }

    override func setUp() { StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset() }

    private func json(_ s: String) -> Data { Data(s.utf8) }
    private let stubServer = KimaServer(baseURL: URL(string: "https://stub.test")!)

    func testDecodesA200Body() async throws {
        StubURLProtocol.handler = { _ in (200, self.json(#"{"id":7}"#)) }
        let item: Item = try await KimaAPIClient.stubbed().get("/things", authed: true)
        XCTAssertEqual(item, Item(id: 7))
    }

    func testAuthHeaderIsSentOnlyWhenAuthed() async throws {
        StubURLProtocol.handler = { _ in (200, self.json(#"{"id":1}"#)) }
        let client = KimaAPIClient.stubbed(credential: .jwt("tok"))
        let _: Item = try await client.get("/a", authed: true)
        let _: Item = try await client.get("/b", authed: false)
        XCTAssertEqual(StubURLProtocol.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertNil(StubURLProtocol.requests[1].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(StubURLProtocol.requests[1].value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(StubURLProtocol.requests[1].cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testApiKeyUsesItsOwnHeader() async throws {
        StubURLProtocol.handler = { _ in (200, self.json(#"{"id":1}"#)) }
        let _: Item = try await KimaAPIClient.stubbed(credential: .apiKey("k")).get("/a", authed: true)
        let req = StubURLProtocol.requests[0]
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "k")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testJSONBodyCarriesContentType() async throws {
        StubURLProtocol.handler = { _ in (200, self.json(#"{"id":1}"#)) }
        let _: Item = try await KimaAPIClient.stubbed().postJSON("/things", body: Body(name: "x"), authed: true)
        let req = StubURLProtocol.requests[0]
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func test401WithoutRefreshTokenIsUnauthorizedAfterOneRequest() async {
        StubURLProtocol.handler = { _ in (401, Data()) }
        do {
            let _: Item = try await KimaAPIClient.stubbed(credential: .apiKey("k")).get("/a", authed: true)
            XCTFail("expected unauthorized")
        } catch APIError.unauthorized {
            XCTAssertEqual(StubURLProtocol.requests.count, 1)
        } catch { XCTFail("wrong error \(error)") }
    }

    func test401RefreshesOnceThenRetriesWithNewToken() async throws {
        let login = KeychainLoginSnapshot()
        defer { login.restore() }
        XCTAssertTrue(KeychainStore.setCredential("old-refresh", for: KeychainStore.refreshToken, server: stubServer))
        StubURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("/auth/refresh") == true {
                return (200, self.json(#"{"token":"new-access","refreshToken":"new-refresh"}"#))
            }
            let auth = req.value(forHTTPHeaderField: "Authorization")
            return auth == "Bearer new-access" ? (200, self.json(#"{"id":3}"#)) : (401, Data())
        }
        let item: Item = try await KimaAPIClient.stubbed(credential: .jwt("old-access")).get("/things", authed: true)
        XCTAssertEqual(item, Item(id: 3))
        let paths = StubURLProtocol.requests.map { $0.url?.path ?? "" }
        XCTAssertEqual(paths.count, 3)
        XCTAssertTrue(paths[1].hasSuffix("/auth/refresh"))
        XCTAssertEqual(paths[0], paths[2])
        // The rotated tokens are saved for the server that issued them.
        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: stubServer), "new-access")
        XCTAssertEqual(KeychainStore.credential(KeychainStore.refreshToken, for: stubServer), "new-refresh")
        XCTAssertNil(KeychainStore.credential(KeychainStore.refreshToken, for: KimaServer(baseURL: URL(string: "https://other.test")!)))
    }

    /// A refresh token saved for another server is never sent here: the 401 comes back as-is.
    func test401NeverSendsAnotherServersRefreshToken() async throws {
        let login = KeychainLoginSnapshot()
        defer { login.restore() }
        let other = KimaServer(baseURL: URL(string: "https://other.test")!)
        XCTAssertTrue(KeychainStore.setCredential("other-refresh", for: KeychainStore.refreshToken, server: other))
        StubURLProtocol.handler = { _ in (401, Data()) }
        do {
            let _: Item = try await KimaAPIClient.stubbed(credential: .jwt("old-access")).get("/things", authed: true)
            XCTFail("expected unauthorized")
        } catch APIError.unauthorized {
            XCTAssertEqual(StubURLProtocol.requests.map { $0.url?.path ?? "" }, ["/api/things"])
        } catch { XCTFail("wrong error \(error)") }
        XCTAssertEqual(KeychainStore.credential(KeychainStore.refreshToken, for: other), "other-refresh")
    }

    func test401AfterRetryIsUnauthorizedWithoutLooping() async throws {
        let login = KeychainLoginSnapshot()
        defer { login.restore() }
        XCTAssertTrue(KeychainStore.setCredential("old-refresh", for: KeychainStore.refreshToken, server: stubServer))
        StubURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("/auth/refresh") == true {
                return (200, self.json(#"{"token":"new-access","refreshToken":"new-refresh"}"#))
            }
            return (401, Data())
        }
        do {
            let _: Item = try await KimaAPIClient.stubbed(credential: .jwt("old-access")).get("/things", authed: true)
            XCTFail("expected unauthorized")
        } catch APIError.unauthorized {
            XCTAssertEqual(StubURLProtocol.requests.count, 3)  // original, refresh, one retry
        } catch { XCTFail("wrong error \(error)") }
    }

    func testNon2xxMapsToHttpWithBody() async {
        StubURLProtocol.handler = { _ in (500, self.json("boom")) }
        do {
            let _: Item = try await KimaAPIClient.stubbed().get("/a", authed: true)
            XCTFail("expected http error")
        } catch APIError.http(let status, let body) {
            XCTAssertEqual(status, 500)
            XCTAssertEqual(body, "boom")
        } catch { XCTFail("wrong error \(error)") }
    }

    func testBadJSONMapsToDecoding() async {
        StubURLProtocol.handler = { _ in (200, self.json("not json")) }
        do {
            let _: Item = try await KimaAPIClient.stubbed().get("/a", authed: true)
            XCTFail("expected decoding error")
        } catch APIError.decoding {
        } catch { XCTFail("wrong error \(error)") }
    }

    func testDeleteCheckedSucceedsOn204AndMaps404() async throws {
        StubURLProtocol.handler = { _ in (204, Data()) }
        try await KimaAPIClient.stubbed().deleteChecked("/things/1", authed: true)
        XCTAssertEqual(StubURLProtocol.requests[0].httpMethod, "DELETE")

        StubURLProtocol.handler = { _ in (404, Data()) }
        do {
            try await KimaAPIClient.stubbed().deleteChecked("/things/1", authed: true)
            XCTFail("expected http error")
        } catch APIError.http(let status, _) {
            XCTAssertEqual(status, 404)
        } catch { XCTFail("wrong error \(error)") }
    }
}
