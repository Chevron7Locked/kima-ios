import Foundation
@testable import Kima

/// A transport that serves one file with byte ranges (206 + Content-Range), in process, recording
/// each range: `RangeFileServer`'s twin for sessions made by the session factory. AVPlayer's own
/// loading never comes through here, so a test that runs both can tell which reads took which road.
final class RangeFileURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var data = Data()
    nonisolated(unsafe) private static var served: [ClosedRange<Int>] = []
    private static let lock = NSLock()

    /// Ranges served, in arrival order.
    static var ranges: [ClosedRange<Int>] { lock.withLock { served } }

    /// How a range is answered.
    enum Reply {
        case serve
        /// 503: a server blip.
        case refuse
        /// Never answered: a stream that stopped sending.
        case hang
    }

    nonisolated(unsafe) private static var replying: (ClosedRange<Int>) -> Reply = { _ in .serve }

    /// Serves `file`, answering each range as `reply` picks.
    static func serve(_ file: Data, reply: @escaping (ClosedRange<Int>) -> Reply = { _ in .serve }) {
        lock.withLock { data = file; served = []; replying = reply }
    }

    /// The adapter: production's posture, this transport answering.
    struct Factory: SessionFactory {
        var protocolClasses: [AnyClass]? { [RangeFileURLProtocol.self] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let file = Self.lock.withLock { Self.data }
        let asked = request.value(forHTTPHeaderField: "Range").flatMap { RangeHeader.range($0, size: file.count) }
        let start = asked?.lowerBound ?? 0, end = asked?.upperBound ?? file.count - 1
        let reply = Self.lock.withLock { Self.served.append(start...end); return Self.replying(start...end) }
        if reply == .hang { return }
        if reply == .refuse {
            let unavailable = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: unavailable, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": "audio/flac",
            "Content-Range": RangeHeader.contentRange(start...end, size: file.count),
            "Content-Length": "\(end - start + 1)",
        ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: file.subdata(in: start..<end + 1))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
