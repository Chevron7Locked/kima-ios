import Foundation
@testable import Kima

/// Canned HTTP responses for unit tests. Build a client with `StubURLProtocol.session()`;
/// set `handler` per test; every request (and its body) is recorded before the handler runs.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (status: Int, body: Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
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

extension KimaAPIClient {
    static func stubbed(credential: KimaCredential = .jwt("test")) -> KimaAPIClient {
        KimaAPIClient(server: KimaServer(baseURL: URL(string: "https://stub.test")!),
                      credential: credential, session: StubURLProtocol.session())
    }
}

extension PlaybackController {
    /// A controller that never touches the audio session and never syncs the queue.
    @MainActor
    static func stubbed(baseURL: String = "https://stub.test") -> PlaybackController {
        let c = PlaybackController(server: KimaServer(baseURL: URL(string: baseURL)!))
        c.engine.activateSession = { _ in }
        c.syncHook = nil
        return c
    }
}
