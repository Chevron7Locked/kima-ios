import Foundation

// Import-initiation methods for KimaAPIClient.
// Endpoints: POST/GET /api/spotify/preview/*, POST /api/spotify/import, POST /api/spotify/import/quick.
// GET /api/spotify/imports and POST /api/spotify/import/:id/cancel already live in
// KimaAPIClient+Notifications.swift — not duplicated here.

extension KimaAPIClient {

    // MARK: - Preview

    /// POST /api/spotify/preview/start — kick off an async preview for a playlist URL.
    /// Accepts Spotify, Deezer, YouTube, SoundCloud, Bandcamp, and Mixcloud URLs.
    /// Returns a jobId; poll via `getPreviewResult` until status != "pending".
    func startPreviewJob(url: String) async throws -> String {
        let body = PreviewStartBody(url: url)
        let r: PreviewStartResponse = try await postJSON("/spotify/preview/start", body: body, authed: true)
        return r.jobId
    }

    /// GET /api/spotify/preview/:jobId — poll for a completed preview result.
    /// Returns `{ status: "pending" }` while the background job is still running.
    /// Redis TTL is 2 hours; results older than that return nil → treat as error.
    func getPreviewResult(jobId: String) async throws -> PreviewJobResult {
        try await get("/spotify/preview/\(jobId)", authed: true)
    }

    // MARK: - Import

    /// POST /api/spotify/import — start a full import backed by a completed preview.
    ///
    /// `albumMbidsToDownload`: for each entry in `preview.albumsToDownload` use
    /// `albumMbid ?? spotifyAlbumId`. Pass `previewJobId` so the server skips re-fetching.
    func startImport(
        spotifyPlaylistId: String,
        playlistName: String,
        albumMbidsToDownload: [String],
        previewJobId: String,
        url: String? = nil
    ) async throws -> StartImportResponse {
        let body = StartImportBody(
            spotifyPlaylistId: spotifyPlaylistId,
            url: url,
            playlistName: playlistName,
            albumMbidsToDownload: albumMbidsToDownload,
            previewJobId: previewJobId
        )
        return try await postJSON("/spotify/import", body: body, authed: true)
    }

    /// POST /api/spotify/import/quick — fire-and-forget import that skips the preview step.
    /// Returns the import jobId; progress surfaces in Activity via import:progress SSE.
    func quickImport(url: String, playlistName: String? = nil) async throws -> String {
        let body = QuickImportBody(url: url, playlistName: playlistName)
        let r: QuickImportResponse = try await postJSON("/spotify/import/quick", body: body, authed: true)
        return r.jobId
    }

}

// MARK: - Request bodies

private struct PreviewStartBody: Encodable { let url: String }
private struct PreviewStartResponse: Decodable { let jobId: String }
private struct QuickImportResponse: Decodable { let jobId: String }

// Zod schema uses .optional() (not .nullish()), so nil optional fields must be *omitted*
// from the JSON body — null would fail validation. Custom encode(to:) uses encodeIfPresent.

private struct QuickImportBody: Encodable {
    let url: String
    let playlistName: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(playlistName, forKey: .playlistName)
    }
    private enum CodingKeys: String, CodingKey { case url, playlistName }
}

private struct StartImportBody: Encodable {
    let spotifyPlaylistId: String
    let url: String?
    let playlistName: String
    let albumMbidsToDownload: [String]
    let previewJobId: String

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(spotifyPlaylistId, forKey: .spotifyPlaylistId)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encode(playlistName, forKey: .playlistName)
        try c.encode(albumMbidsToDownload, forKey: .albumMbidsToDownload)
        try c.encode(previewJobId, forKey: .previewJobId)
    }
    private enum CodingKeys: String, CodingKey {
        case spotifyPlaylistId, url, playlistName, albumMbidsToDownload, previewJobId
    }
}

// MARK: - Response models (internal — used by ImportViewModel / ImportView)

struct StartImportResponse: Decodable {
    let jobId: String
    let status: String
    let message: String?
}

/// Outer envelope from GET /api/spotify/preview/:jobId.
struct PreviewJobResult: Decodable {
    let status: String          // "pending" | "completed" | "error"
    let preview: ImportPreview?
    let error: String?
    let userId: String?
}

/// Full preview result from the server's async preview job. `matchedTracks` (large per-track array) is omitted:
/// iOS only needs the summary counts and album list to build the import request.
// All four types decode defensively; `albumsToDownload` is decoded per element via FailableDecodable, so one
// messy row (missing artist, null field, deleted account) drops only that row instead of blanking the preview.
struct ImportPreview: Decodable {
    let playlist: PreviewPlaylist
    let summary: PreviewSummary
    let albumsToDownload: [AlbumToDownload]

    private enum K: String, CodingKey { case playlist, summary, albumsToDownload }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        playlist = try c.decode(PreviewPlaylist.self, forKey: .playlist)   // itself lenient — won't throw on bad fields
        summary  = try c.decode(PreviewSummary.self, forKey: .summary)
        albumsToDownload = ((try? c.decode([FailableDecodable<AlbumToDownload>].self, forKey: .albumsToDownload)) ?? []).compactMap(\.value)
    }
}

struct PreviewPlaylist: Decodable {
    let id: String
    let name: String
    let description: String?
    let owner: String
    let imageUrl: String?
    let trackCount: Int

    private enum K: String, CodingKey { case id, name, description, owner, imageUrl, trackCount }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id          = (try? c.decode(String.self, forKey: .id))    ?? ""
        name        = (try? c.decode(String.self, forKey: .name))  ?? "playlist"
        description =  try? c.decode(String.self, forKey: .description)
        owner       = (try? c.decode(String.self, forKey: .owner)) ?? ""
        imageUrl    =  try? c.decode(String.self, forKey: .imageUrl)
        trackCount  = (try? c.decode(Int.self, forKey: .trackCount)) ?? 0
    }
}

struct PreviewSummary: Decodable {
    let total: Int
    let inLibrary: Int
    let downloadable: Int
    let notFound: Int

    private enum K: String, CodingKey { case total, inLibrary, downloadable, notFound }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        total        = (try? c.decode(Int.self, forKey: .total))        ?? 0
        inLibrary    = (try? c.decode(Int.self, forKey: .inLibrary))    ?? 0
        downloadable = (try? c.decode(Int.self, forKey: .downloadable)) ?? 0
        notFound     = (try? c.decode(Int.self, forKey: .notFound))     ?? 0
    }
}

struct AlbumToDownload: Decodable {
    let spotifyAlbumId: String
    let albumName: String
    let artistName: String
    let albumMbid: String?
    /// Identifier to send in `albumMbidsToDownload`. Prefers MusicBrainz MBID; falls back
    /// to Spotify album ID (the server accepts either via `.includes(a.albumMbid || a.spotifyAlbumId)`).
    var downloadId: String { albumMbid ?? spotifyAlbumId }

    private enum K: String, CodingKey { case spotifyAlbumId, albumName, artistName, albumMbid }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        spotifyAlbumId = (try? c.decode(String.self, forKey: .spotifyAlbumId)) ?? ""
        albumName      = (try? c.decode(String.self, forKey: .albumName))      ?? "unknown album"
        artistName     = (try? c.decode(String.self, forKey: .artistName))     ?? "unknown artist"
        albumMbid      =  try? c.decode(String.self, forKey: .albumMbid)
    }
}
