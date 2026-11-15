import Foundation
import XCTest
@testable import Kima

/// Canned HTTP responses for unit tests, installed by `StubSessionFactory`. Set `handler` per
/// test; every request (and its body) is recorded before the handler runs.
///
/// Serialization is part of the contract: URLSession calls `startLoading` inline on one serial
/// queue per session, so requests through ONE client run one at a time — a `Thread.sleep` in a
/// handler blocks its sibling requests on that client. Separate `.stubbed()` clients are separate
/// sessions answering concurrently. A test whose timing depends on one request waiting for
/// another must therefore wire those requests through a single shared client — which is also how
/// production wires every path (one `env.client`).
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (status: Int, body: Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []

    static func reset() { handler = nil; requests = []; bodies = [] }

    /// Requests whose path ends with `suffix`, with their bodies decoded as JSON objects.
    static func posts(to suffix: String) -> [[String: Any]] {
        zip(requests, bodies).compactMap { req, body in
            guard req.url?.path.hasSuffix(suffix) == true else { return nil }
            return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        Self.bodies.append(Self.body(of: request))
        let (status, body) = Self.handler?(request) ?? (404, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    /// URLSession hands a protocol its upload body as a stream.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

/// The test-stub adapter (ticket 08): production's posture by construction — one shared
/// `makeSession` includes the trust delegate — with stub transports answering instead of the
/// network. It cannot drift from what it claims to mirror; that is the point of two adapters
/// over duplicated bodies.
struct StubSessionFactory: SessionFactory {
    var protocolClasses: [AnyClass]? = [StubURLProtocol.self]
}

/// A transport that never answers: every request fails at the connection level, no HTTP status,
/// for the branches that must tell *server unreachable* from any HTTP reply (`APIError.network`).
final class FailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

extension XCTestCase {
    /// A recorded request's query items as a dictionary, for asserting on request shape.
    @MainActor
    func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }
}

extension KimaAPIClient {
    static func stubbed(credential: KimaCredential = .jwt("test")) -> KimaAPIClient {
        KimaAPIClient(server: KimaServer(baseURL: URL(string: "https://stub.test")!),
                      credential: credential, sessions: StubSessionFactory())
    }
}

extension PlaybackController {
    /// A controller that never touches the audio session and never syncs the queue.
    @MainActor
    static func stubbed(baseURL: String = "https://stub.test") -> PlaybackController {
        let c = PlaybackController(server: KimaServer(baseURL: URL(string: baseURL)!))
        c.engine.activateSession = { _ in }
        c.syncHook = nil
        // Load paths ask the stream source for playable URLs (ticket 13); wire one to the stub
        // transport so mint-and-load behavior works as it did through `apiClient`. The client's
        // host is always stub.test — only the controller's server shapes the stream URLs.
        c.streamSource = StreamSource(server: c.server, client: .stubbed())
        return c
    }
}
