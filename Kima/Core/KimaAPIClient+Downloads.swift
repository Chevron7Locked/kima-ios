import Foundation

// MARK: - Download Models
// Endpoints in this file: POST /api/downloads (queue), GET /api/notifications/downloads/active (in-flight),
// DELETE /api/downloads/:id and /clear-all, GET /api/downloads/failed, DELETE /api/downloads/failed/:id.

/// Nested JSON stored in a DownloadJob's `metadata` field.
/// Only fields the UI cares about are decoded; additional keys are ignored.
struct DownloadJobMetadata: Codable {
    /// Human-readable current activity text ("Searching Lidarr…", etc.)
    let statusText: String?
    /// Which backend source is active — "lidarr" renders purple in the web.
    let currentSource: String?
    /// "library" | "discovery"
    let downloadType: String?
    let artistName: String?
    let albumTitle: String?
}

/// A single Lidarr acquisition job, as the server stores it.
struct DownloadJob: Codable, Identifiable {
    let id: String
    /// Display label, e.g. "Radiohead - OK Computer".
    let subject: String
    /// "album" | "artist"
    let type: String
    /// "pending" | "processing" | "completed" | "failed" | "exhausted"
    let status: String
    /// ISO 8601 string. Parse lazily — no custom date strategy needed.
    let createdAt: String
    let metadata: DownloadJobMetadata?
}

/// Server response to POST /api/downloads.
struct CreateDownloadResponse: Codable {
    let id: String?
    let status: String?
    let message: String?
    /// True when an identical job was already queued.
    let duplicate: Bool?
    /// Artist downloads fan out; this is the count of album jobs spawned.
    let albumCount: Int?
}

/// A "failed / unavailable" album notification.
///
/// Shape: `UnavailableAlbum` Prisma model (downloads/failed).
/// Fields left unused by the UI are omitted (similarity, tier, weekStartDate, etc.)
struct FailedAlbum: Codable, Identifiable {
    let id: String
    let artistName: String
    let albumTitle: String
    let albumMbid: String
    let createdAt: String?
}

// MARK: - Request body helpers (private, Encodable only)

private struct DownloadAlbumBody: Encodable {
    let type = "album"
    let subject: String
    let mbid: String
    let artistName: String
    let albumTitle: String
    let downloadType: String
}

private struct DownloadArtistBody: Encodable {
    let type = "artist"
    let subject: String
    let mbid: String
    let downloadType: String
}

// MARK: - KimaAPIClient extension

extension KimaAPIClient {

    // MARK: Trigger downloads

    /// POST /api/downloads — queue a single album acquisition via Lidarr.
    /// `rgMbid` is the release-group MBID identifying the album on MusicBrainz;
    /// `downloadType` is "library" (default) or "discovery" (discovery folder).
    func downloadAlbum(
        artistName: String,
        albumTitle: String,
        rgMbid: String,
        downloadType: String = "library"
    ) async throws -> CreateDownloadResponse {
        let body = DownloadAlbumBody(
            subject: "\(artistName) - \(albumTitle)",
            mbid: rgMbid,
            artistName: artistName,
            albumTitle: albumTitle,
            downloadType: downloadType
        )
        return try await postJSON("/downloads", body: body, authed: true)
    }

    /// POST /api/downloads — queue all albums for an artist via Lidarr.
    /// `downloadType` is "library" (default) or "discovery".
    func downloadArtist(
        name: String,
        mbid: String,
        downloadType: String = "library"
    ) async throws -> CreateDownloadResponse {
        let body = DownloadArtistBody(
            subject: name,
            mbid: mbid,
            downloadType: downloadType
        )
        return try await postJSON("/downloads", body: body, authed: true)
    }

    // MARK: Active download list

    /// GET /api/notifications/downloads/active — pending and processing jobs only.
    ///
    /// Mirrors the web's `useActiveDownloads` hook (uses the notifications sub-route,
    /// not GET /downloads, to get the correctly-filtered active-only set).
    func getActiveDownloads() async throws -> [DownloadJob] {
        try await get("/notifications/downloads/active", authed: true)
    }

    // MARK: Cancel / remove

    /// DELETE /api/downloads/:id — cancel and remove a download job.
    ///
    /// Idempotent: the server returns success even if the job was already absent.
    func deleteDownload(id: String) async throws {
        try await deleteChecked("/downloads/\(id)", authed: true)
    }

    // MARK: Failed album notifications

    /// GET /api/downloads/failed — unavailable album notifications for the user.
    func getFailedDownloads() async throws -> [FailedAlbum] {
        try await get("/downloads/failed", authed: true)
    }

    /// DELETE /api/downloads/failed/:id — dismiss a single failed-album notification.
    func deleteFailedDownload(id: String) async throws {
        try await deleteChecked("/downloads/failed/\(id)", authed: true)
    }

}
