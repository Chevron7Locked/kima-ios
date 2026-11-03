import Foundation

// MARK: - Discover Weekly domain models
//
// Shapes and endpoints for Discover Weekly.

/// Similarity tier of a discovered track / album (Last.fm sourced).
/// Raw values match backend strings; `low` and `wild` are legacy aliases kept for backward compat.
enum DiscoverTier: String, Codable, Sendable {
    case high, medium, explore, wildcard
    case low, wild   // legacy — server may return these on older playlists

    var label: String {
        switch self {
        case .high:             return "high match"
        case .medium:           return "medium match"
        case .explore, .low:    return "explore"
        case .wildcard, .wild:  return "wild card"
        }
    }

    /// Editorial priority for promoting the week's single best pick to the featured hero
    /// card — a strong Last.fm match wins over a wild card, which wins over an explore-tier
    /// long shot. Used only for choosing/ordering the crate; the tier label/color are
    /// unaffected.
    var editorialRank: Int {
        switch self {
        case .high:             return 3
        case .wildcard, .wild:  return 2
        case .medium:           return 1
        case .explore, .low:    return 0
        }
    }
}

/// A single track in the Discover Weekly playlist.
struct DiscoverTrack: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let albumId: String
    var isLiked: Bool
    let likedAt: String?
    let similarity: Double
    let tier: DiscoverTier
    let coverUrl: String?
    let available: Bool
    let duration: Double
}

/// An album that was recommended but could not be indexed / downloaded.
struct UnavailableAlbum: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let albumId: String
    /// The albumId of the original recommendation this entry replaced (decode-only).
    /// The retry flow may need it to map a replacement back to its source. Optional —
    /// older server responses omit it; absent → nil.
    let originalAlbumId: String?
    let similarity: Double
    let tier: DiscoverTier
    let previewUrl: String?
    let deezerTrackId: String?
    let deezerAlbumId: String?
    let available: Bool
    let attemptNumber: Int?
}

/// Full Discover Weekly playlist returned by GET /discover/current.
struct DiscoverPlaylist: Codable, Sendable {
    let weekStart: String
    let weekEnd: String
    var tracks: [DiscoverTrack]
    let unavailable: [UnavailableAlbum]
    let totalCount: Int
    let unavailableCount: Int
    /// Server flag that the playlist data may be out of date (decode-only). Optional —
    /// absent on older responses → nil → indicator hidden. Drives a subtle "may be stale"
    /// chip in the hero when explicitly true.
    let stale: Bool?
}

// MARK: - Editorial helpers

extension DiscoverPlaylist {
    /// The week's single best recommendation — highest match tier, then highest raw
    /// similarity among available tracks — promoted out of the flat list into the
    /// featured hero card. Falls back to the first track if none are marked available
    /// (defensive; `unavailable` albums normally live in a separate array already).
    var featuredPick: DiscoverTrack? {
        tracks
            .filter { $0.available }
            .max { lhs, rhs in
                if lhs.tier.editorialRank != rhs.tier.editorialRank {
                    return lhs.tier.editorialRank < rhs.tier.editorialRank
                }
                return lhs.similarity < rhs.similarity
            }
            ?? tracks.first
    }
}

/// Active generation batch status (GET /discover/batch-status).
struct DiscoverBatchStatus: Codable, Sendable {
    let active: Bool
    let status: String?    // "scanning" | "downloading" | null
    let batchId: String?
    let progress: Int?
    let completed: Int?
    let failed: Int?
    let total: Int?
}

// MARK: - Private response envelopes

private struct GenerateResponse: Codable, Sendable {
    let message: String
    let jobId: String?
}

private struct SuccessResponse: Codable, Sendable {
    let success: Bool
}

private struct RetryResponse: Codable, Sendable {
    let success: Bool
    let queued: Int
    let batchId: String?
    let message: String
}

private struct AlbumIdBody: Encodable, Sendable { let albumId: String }

// MARK: - KimaAPIClient discover extension

extension KimaAPIClient {

    // MARK: Playlist

    /// GET /discover/current
    func getCurrentDiscoverWeekly() async throws -> DiscoverPlaylist {
        try await get("/discover/current", authed: true)
    }

    // MARK: Generation

    /// POST /discover/generate — trigger weekly playlist generation.
    @discardableResult
    func generateDiscoverWeekly() async throws -> String {
        let r: GenerateResponse = try await postJSON(
            "/discover/generate", body: EmptyRequestBody(), authed: true
        )
        return r.message
    }

    /// GET /discover/batch-status — poll generation progress.
    func getDiscoverBatchStatus() async throws -> DiscoverBatchStatus {
        try await get("/discover/batch-status", authed: true)
    }

    /// DELETE /discover/batch — cancel the active generation batch.
    /// Uses `deleteChecked` (throws on any non-2xx) so the VM can keep the user in the
    /// generating state and surface an error when the server refuses the cancel.
    func cancelDiscoverBatch() async throws {
        try await deleteChecked("/discover/batch", authed: true)
    }

    // MARK: Like / Unlike

    /// POST /discover/like { albumId }
    func likeDiscoverAlbum(albumId: String) async throws {
        let _: SuccessResponse = try await postJSON(
            "/discover/like", body: AlbumIdBody(albumId: albumId), authed: true
        )
    }

    /// DELETE /discover/unlike { albumId }
    func unlikeDiscoverAlbum(albumId: String) async throws {
        try await deleteJSON(
            "/discover/unlike", body: AlbumIdBody(albumId: albumId), authed: true
        )
    }

    // MARK: Unavailable

    /// POST /discover/retry-unavailable — re-queue failed album downloads.
    func retryUnavailableAlbums() async throws -> (queued: Int, message: String) {
        let r: RetryResponse = try await postJSON(
            "/discover/retry-unavailable", body: EmptyRequestBody(), authed: true
        )
        return (r.queued, r.message)
    }
}
