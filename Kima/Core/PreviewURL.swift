import Foundation

/// Builds authenticated preview-stream URLs for missing/unowned tracks, via the server's on-the-fly preview
/// endpoint (it proxies Deezer or similar): `GET {base}/api/artists/preview/{artist}/{title}/stream?token={token}`.
/// Uses query-token auth like `StreamURL`, since AVPlayer cannot inject Bearer headers. Pure path/query
/// shapes; the token comes from `StreamSource.previewURL(artistName:trackTitle:)`, the only caller.
enum PreviewURL {

    /// Build a preview stream URL from artist name + track title.
    /// Both path segments are percent-encoded for the URL path (not query).
    static func track(
        base: KimaServer,
        artistName: String,
        trackTitle: String,
        token: String
    ) -> URL? {
        base.api(
            "/artists/preview/\(KimaServer.pathSegment(artistName))/\(KimaServer.pathSegment(trackTitle))/stream",
            query: ["token": token]
        )
    }
}
