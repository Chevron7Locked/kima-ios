import Foundation

/// Builds authenticated preview-stream URLs for missing/unowned tracks, via the server's on-the-fly preview
/// endpoint (it proxies Deezer or similar): `GET {base}/api/artists/preview/{artist}/{title}/stream?token={jwt}`.
/// Uses query-token auth like `StreamURL`, since AVPlayer cannot inject Bearer headers.
enum PreviewURL {

    /// Build a preview stream URL from artist name + track title.
    ///
    /// Returns nil when `token` is nil — callers should hide the preview action in that case.
    /// Both path segments are percent-encoded for the URL path (not query).
    static func track(
        base: KimaServer,
        artistName: String,
        trackTitle: String,
        token: String?
    ) -> URL? {
        let encodedArtist = KimaServer.pathSegment(artistName)
        let encodedTitle = KimaServer.pathSegment(trackTitle)
        var query: [String: String] = [:]
        if let token { query["token"] = token }
        return base.api(
            "/artists/preview/\(encodedArtist)/\(encodedTitle)/stream",
            query: query
        )
    }
}
