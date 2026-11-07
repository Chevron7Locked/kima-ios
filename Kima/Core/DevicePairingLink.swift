import Foundation

/// The 6-character code the Kima website shows for linking a device.
enum DevicePairingCode {
    static let length = 6
    static let characters = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// The code trimmed and uppercased, or nil when it is not a well-formed code.
    static func normalized(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == length, code.unicodeScalars.allSatisfy(characters.contains) else { return nil }
        return code
    }
}

/// A `kima://link?code=<code>&server=<url-encoded origin>` link, which the website's "link a device"
/// page shows as a QR code. Unlike the share link, this one names a server, so it is never acted on by
/// itself: the person confirms the host before anything is sent.
struct DevicePairingLink: Equatable {
    enum ParseResult: Equatable {
        /// Not a link-a-device URL at all: some other string or a different kima link.
        case notPairing
        /// A link-a-device URL that fails validation.
        case invalid
        case link(DevicePairingLink)
    }

    let code: String
    let server: KimaServer

    /// The server address points at the machine showing the QR code, so a phone can never reach it.
    var isLoopback: Bool {
        guard var host = server.baseURL.host(percentEncoded: false)?.lowercased() else { return false }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        while host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("::ffff:") {   // IPv4-mapped, written dotted or as two hex groups
            let mapped = host.dropFirst("::ffff:".count)
            return mapped.hasPrefix("127.") || mapped == "0.0.0.0" || mapped.hasPrefix("7f")
        }
        return host == "localhost" || host.hasSuffix(".localhost") || host == "::1"
            || host == "0.0.0.0" || host.hasPrefix("127.")
    }

    var usesCleartext: Bool { server.baseURL.scheme == "http" }

    static let maxLength = 512

    static func parse(_ url: URL) -> ParseResult { parse(url.absoluteString) }

    static func parse(_ string: String) -> ParseResult {
        let lower = string.lowercased()
        guard lower.hasPrefix("kima://link") else { return .notPairing }
        guard string.count <= maxLength,
              let parts = URLComponents(string: string),
              parts.scheme?.lowercased() == "kima",
              parts.host?.lowercased() == "link" else {
            return lower.hasPrefix("kima://link?") || lower == "kima://link" ? .invalid : .notPairing
        }
        guard parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty, parts.fragment == nil,
              let items = parts.queryItems, items.count == 2,
              items.filter({ $0.name == "code" }).count == 1,
              items.filter({ $0.name == "server" }).count == 1,
              let rawCode = items.first(where: { $0.name == "code" })?.value,
              let code = DevicePairingCode.normalized(rawCode),
              let rawServer = items.first(where: { $0.name == "server" })?.value,
              let server = serverOrigin(rawServer) else { return .invalid }
        return .link(DevicePairingLink(code: code, server: server))
    }

    private static let hostCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-._:")

    /// `scheme://host[:port]` rebuilt from the parsed parts. Userinfo, a path, a query and a fragment are
    /// refused, so `https://listen.example@evil.test` can't pass for `listen.example`.
    private static func serverOrigin(_ raw: String) -> KimaServer? {
        guard let parts = URLComponents(string: raw),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = parts.host?.lowercased(), !host.isEmpty,
              { if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }; return true }(),
              !host.isEmpty, host.unicodeScalars.allSatisfy(hostCharacters.contains),
              parts.user == nil, parts.password == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.query == nil, parts.fragment == nil else { return nil }
        var origin = URLComponents()
        origin.scheme = scheme
        origin.host = host.contains(":") ? "[\(host)]" : host   // an IPv6 literal is bracketed in a URL
        origin.port = parts.port
        guard let url = origin.url else { return nil }
        return KimaServer(baseURL: url)
    }
}
