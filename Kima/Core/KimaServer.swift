import Foundation

/// The user's Kima server connection: a base URL + how to build `/api/...` URLs.
struct KimaServer: Equatable {
    /// e.g. https://kima.example.com  (no trailing /api — we add it)
    var baseURL: URL

    /// `<base>/api/<path>`, keeping any base path prefix (`https://host/kima` → `https://host/kima/api/…`).
    /// Callers pass an already-encoded path (encode each id segment once with `pathSegment`); a raw
    /// character that would make `URLComponents` trap is encoded here instead of crashing.
    func api(_ path: String, query: [String: String] = [:]) -> URL {
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL.appending(path: "api").appending(path: clean)
        }
        var prefix = components.percentEncodedPath
        while prefix.hasSuffix("/") { prefix.removeLast() }
        let joined = prefix + "/api/" + clean
        components.percentEncodedPath = Self.isEncodedPath(joined)
            ? joined
            : (joined.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "/api")
        components.percentEncodedQuery = query.isEmpty ? nil : query
            .sorted { $0.key < $1.key }
            .map { "\(Self.queryComponent($0.key))=\(Self.queryComponent($0.value))" }
            .joined(separator: "&")
        components.fragment = nil
        return components.url ?? baseURL.appending(path: "api").appending(path: clean)
    }
}

extension KimaServer {
    /// Percent-encode one URL path segment, slashes included (JS `encodeURIComponent` for paths).
    static func pathSegment(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// True when every scalar is legal in a path and every `%` starts a two-hex-digit escape.
    private static func isEncodedPath(_ s: String) -> Bool {
        let scalars = Array(s.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if c == "%" {
                guard i + 2 < scalars.count,
                      scalars[i + 1].properties.isASCIIHexDigit,
                      scalars[i + 2].properties.isASCIIHexDigit else { return false }
                i += 3
                continue
            }
            if !CharacterSet.urlPathAllowed.contains(c) { return false }
            i += 1
        }
        return true
    }

    /// Query keys/values: like `urlQueryAllowed` but `+ & = ? #` are escaped so they survive literally.
    private static func queryComponent(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
