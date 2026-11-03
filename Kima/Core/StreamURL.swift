import Foundation

/// Builds `?token=` stream URLs for AVPlayer, which cannot send an auth header. The token is
/// whatever `PlaybackController.resolveStreamToken` returns.
enum StreamURL {

    /// Track stream URL — hits the server, triggering a server-side Play row (scrobble).
    /// `GET {base}/api/library/tracks/{trackId}/stream?token={token}`.
    /// Ids are server-issued cuids; encoding is the belt for the path (no-op on valid ids).
    static func track(base: KimaServer, trackId: String, token: String) -> URL? {
        base.api("/library/tracks/\(KimaServer.pathSegment(trackId))/stream", query: ["token": token])
    }

    // Long-form stream URLs

    /// Audiobook file stream URL: `GET {base}/api/audiobooks/{bookId}/stream?trackIndex={index}&token={token}`.
    /// `index` is the 1-based `AudiobookTrack.index`; when 0, `trackIndex` is omitted and the server
    /// plays the first file. `token` comes from `resolveStreamToken`.
    static func audiobook(base: KimaServer, bookId: String, index: Int, token: String) -> URL? {
        var query: [String: String] = ["token": token]
        if index > 0 { query["trackIndex"] = "\(index)" }
        return base.api("/audiobooks/\(KimaServer.pathSegment(bookId))/stream", query: query)
    }

    /// Podcast episode stream URL: `GET {base}/api/podcasts/{podcastId}/episodes/{episodeId}/stream?token={token}`.
    /// The endpoint accepts `?token=` auth, which AVPlayer needs because it can't set headers without `AVURLAsset`.
    static func podcastEpisode(base: KimaServer, podcastId: String, episodeId: String, token: String) -> URL? {
        base.api("/podcasts/\(KimaServer.pathSegment(podcastId))/episodes/\(KimaServer.pathSegment(episodeId))/stream", query: ["token": token])
    }

    /// A not-followed show's first episode, streamed through the server and stored nowhere:
    /// `GET {base}/api/podcasts/preview/{itunesId}/snippet?token={token}`.
    static func podcastSnippet(base: KimaServer, itunesId: String, token: String) -> URL? {
        base.api("/podcasts/preview/\(KimaServer.pathSegment(itunesId))/snippet", query: ["token": token])
    }
}
