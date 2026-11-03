import Foundation

/// Port of the web `getCoverArtUrl(coverId, size?)`. `/audiobooks/…` and `/podcasts/…` go direct to
/// `{base}/api{coverId}`; http(s):// and native: ids go through `/api/library/cover-art?url=`; any
/// other id is one percent-encoded path segment of `/api/library/cover-art/` (like encodeURIComponent).
/// No token in the URL: callers authenticate with headers.
enum CoverArtURL {

    /// Builds a cover-art URL from an API cover id (`coverArt`, `coverUrl`, etc.), or nil if it can't be built.
    /// No credential is in the URL; auth goes in a request header so the token stays out of access logs.
    /// `size` is the desired pixel dimension and is omitted from the URL when nil.
    static func url(base: KimaServer, coverId: String, size: Int?) -> URL? {
        var query: [String: String] = [:]
        if let size { query["size"] = "\(size)" }

        // /audiobooks/… and /podcasts/… → direct endpoints (not proxied), matching the web
        if coverId.hasPrefix("/audiobooks/") || coverId.hasPrefix("/podcasts/") {
            return base.api(coverId, query: query)
        }

        // External or native-scheme URLs → proxy via ?url= query param.
        // URLQueryItem in api(_:query:) handles percent-encoding of the url value.
        if coverId.hasPrefix("http://") || coverId.hasPrefix("https://") || coverId.hasPrefix("native:") {
            var proxyQuery = query
            proxyQuery["url"] = coverId
            return base.api("/library/cover-art", query: proxyQuery)
        }

        // Everything else → one percent-encoded path segment on the cover-art proxy (see header).
        let proxyBase = base.baseURL
            .appending(path: "api",        directoryHint: .notDirectory)
            .appending(path: "library",    directoryHint: .notDirectory)
            .appending(path: "cover-art",  directoryHint: .notDirectory)
            .appending(component: coverId, directoryHint: .notDirectory)
        guard var comps = URLComponents(url: proxyBase, resolvingAgainstBaseURL: false) else { return nil }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return comps.url
    }
}
