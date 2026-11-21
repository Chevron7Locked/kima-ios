import Darwin
import Foundation
@testable import Kima

/// A loopback HTTP server that serves one file with byte ranges, like the hub's stream route, and
/// records each request's range. Real sockets, because AVPlayer's own loading never goes through
/// URLProtocol stubs.
final class RangeFileServer {
    private var serverFD: Int32 = -1
    private let lock = NSLock()
    private var _ranges: [ClosedRange<Int>] = []
    private let data: Data
    private let mime: String
    private let honorsRanges: Bool
    private(set) var port = 0
    /// Seconds to hold each reply before sending it, by the range asked for: a slow server, for
    /// tests that need something to land while a request is out.
    var delay: (ClosedRange<Int>) -> TimeInterval = { _ in 0 }
    /// Whether to answer a request with 503 instead, by the range asked for: a server blip.
    var refuse: (ClosedRange<Int>) -> Bool = { _ in false }

    /// Ranges served, in arrival order.
    var ranges: [ClosedRange<Int>] { lock.withLock { _ranges } }
    var url: URL { URL(string: "http://127.0.0.1:\(port)/api/library/tracks/t1/stream?token=x")! }

    /// The session a test's own reads take: production's posture, as the engine's are.
    static let session = ProductionSessionFactory.production.makeSession()
    /// This server's file as the FLAC code reads it.
    var byteSource: FLACByteSource { .http(url, session: Self.session) }

    /// `honorsRanges: false` answers every request with the whole file (200), like a server without range support.
    init(data: Data, mime: String = "audio/flac", honorsRanges: Bool = true) {
        self.data = data
        self.mime = mime
        self.honorsRanges = honorsRanges
    }

    func start() throws {
        signal(SIGPIPE, SIG_IGN)   // AVPlayer drops connections mid-body; a write must not kill the host
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        guard bound == 0, listen(fd, 16) == 0 else { close(fd); throw POSIXError(.EADDRINUSE) }
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        serverFD = fd
        port = Int(addr.sin_port.byteSwapped)
        Thread.detachNewThread { [self] in
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                var one: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                Thread.detachNewThread { [self] in serve(client) }
            }
        }
    }

    func stop() {
        if serverFD >= 0 { close(serverFD) }
        serverFD = -1
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        var buf = [UInt8](repeating: 0, count: 8192)
        var request = ""
        while request.range(of: "\r\n\r\n") == nil {
            let n = read(fd, &buf, buf.count)
            guard n > 0 else { return }
            request += String(decoding: buf[0..<n], as: UTF8.self)
        }
        let line = request.split(separator: "\r\n").first { $0.lowercased().hasPrefix("range:") }
        let (bytes, partial) = RangeHeader.served(honorsRanges ? line.map(String.init) : nil, size: data.count)
        let start = bytes.lowerBound, end = bytes.upperBound
        lock.withLock { _ranges.append(start...end) }
        let wait = delay(start...end)
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        if refuse(start...end) {
            let reply = "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            _ = reply.utf8CString.withUnsafeBufferPointer { write(fd, $0.baseAddress!, $0.count - 1) }
            return
        }
        var head = partial
            ? "HTTP/1.1 206 Partial Content\r\nContent-Range: \(RangeHeader.contentRange(start...end, size: data.count))\r\n"
            : "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: \(mime)\r\n" + (honorsRanges ? "Accept-Ranges: bytes\r\n" : "")
        head += "Content-Length: \(end - start + 1)\r\nConnection: close\r\n\r\n"
        _ = head.utf8CString.withUnsafeBufferPointer { write(fd, $0.baseAddress!, $0.count - 1) }
        data.withUnsafeBytes { raw in
            var sent = 0
            let length = end - start + 1
            while sent < length {
                let n = write(fd, raw.baseAddress! + start + sent, min(65_536, length - sent))
                guard n > 0 else { return }
                sent += n
            }
        }
    }
}
