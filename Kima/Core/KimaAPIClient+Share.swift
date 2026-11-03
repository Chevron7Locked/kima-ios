import Foundation

// Share-link API. POST /share creates or returns the link (auth); GET /share/:token resolves it (no auth);
// DELETE /share/:token revokes it (owner only). Cover art and streaming for shared content need no auth either:
// GET /share/:token/cover-art/:coverArtId and /share/:token/stream/:trackId.

// MARK: - Response model: share link creation

/// Response from POST /api/share. The token is used to build kima://share/<token> deep links.
struct ShareLinkResponse: Codable, Sendable {
    let token: String
    /// Relative URL returned by the server — unused on the client; we build the deep link.
    let url: String
    /// True when the server returned an existing active link rather than creating a new one.
    let existing: Bool?
}

// MARK: - Shared entity sub-types

struct SharedArtistRef: Codable, Sendable {
    let id: String?
    let name: String?
}

/// Album stub embedded in a shared track item. The authed playlists endpoint aliases
/// the Prisma `coverUrl` column to `coverArt`; the public share endpoint returns the
/// raw column, so both keys are accepted defensively.
struct SharedTrackAlbum: Codable, Sendable {
    let id: String?
    let title: String?
    let coverUrl: String?   // raw Prisma column — present on share responses
    let coverArt: String?   // aliased name — accepted defensively
    let artist: SharedArtistRef?

    /// First non-nil cover identifier for building the share cover-art URL.
    var effectiveCoverId: String? { coverUrl ?? coverArt }
}

/// One track embedded in a shared playlist or album entity.
struct SharedTrack: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let duration: Double        // seconds
    let trackNo: Int?
    let discNumber: Int?
    let discSubtitle: String?
    let album: SharedTrackAlbum?
}

/// One sort-ordered slot in a shared playlist.
struct SharedPlaylistItem: Codable, Sendable, Identifiable {
    let id: String
    let sort: Int?
    let track: SharedTrack
}

/// Full shared playlist entity (returned when entityType == "playlist").
struct SharedPlaylist: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let items: [SharedPlaylistItem]?
    let user: PlaylistUser?     // { username } — reuses the existing summary type
}

/// Full shared album entity (returned when entityType == "album").
/// The track projection is id/title/trackNo/discNumber/discSubtitle/duration only.
struct SharedAlbum: Codable, Sendable, Identifiable {
    let id: String
    let title: String?
    let coverArt: String?       // Prisma scalar — may be absent if the album has no art
    let coverUrl: String?       // accepted defensively
    let artist: SharedArtistRef?
    let tracks: [SharedTrack]

    var effectiveCoverId: String? { coverArt ?? coverUrl }
}

/// Discriminated union of the three shareable entity types.
enum SharedEntity: Sendable {
    case playlist(SharedPlaylist)
    case track(SharedTrack)
    case album(SharedAlbum)
}

/// Top-level response from GET /api/share/:token. Custom Decodable: reads `entityType`
/// first, then decodes the polymorphic `entity` field into the right concrete type.
struct SharedContent: Decodable, Sendable {
    let entityType: String
    let entity: SharedEntity
    let createdAt: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try c.decode(String.self, forKey: .entityType)
        entityType = rawType
        createdAt  = try c.decodeIfPresent(String.self, forKey: .createdAt)

        switch rawType {
        case "playlist":
            entity = .playlist(try c.decode(SharedPlaylist.self, forKey: .entity))
        case "track":
            entity = .track(try c.decode(SharedTrack.self, forKey: .entity))
        case "album":
            entity = .album(try c.decode(SharedAlbum.self, forKey: .entity))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .entity, in: c,
                debugDescription: "Unknown entityType '\(rawType)' in share response"
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case entityType, entity, createdAt
    }
}

// MARK: - Request bodies

private struct CreateShareBody: Encodable, Sendable {
    let entityType: String
    let entityId: String
}

// MARK: - KimaAPIClient extension

extension KimaAPIClient {

    /// GET /api/share/:token — resolve a public share link. No auth required.
    /// - Throws `APIError.http(404, _)` for unknown tokens.
    /// - Throws `APIError.http(410, _)` for expired or play-limit-exhausted tokens.
    func sharedContent(token: String) async throws -> SharedContent {
        try await get("/share/\(token)", authed: false)
    }

    /// POST /api/share — create (or return an existing) share link.
    /// `entityType` must be `"playlist"`, `"track"`, or `"album"` (validated server-side).
    /// The server is idempotent: if an active link already exists for the same entity and
    /// owner it is returned unchanged (`existing: true`).
    func createShareLink(entityType: String, entityId: String) async throws -> ShareLinkResponse {
        let body = CreateShareBody(entityType: entityType, entityId: entityId)
        return try await postJSON("/share", body: body, authed: true)
    }

    /// DELETE /api/share/:token — turn a share link off (owner only).
    func revokeShareLink(token: String) async throws {
        try await deleteChecked("/share/\(KimaServer.pathSegment(token))", authed: true)
    }

    /// The web page for a share link, `<server>/share/<token>`: opens in any browser, no sign-in.
    nonisolated func shareLinkURL(token: String) -> URL {
        server.baseURL.appending(path: "share").appending(path: token)
    }

}
