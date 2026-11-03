import Foundation

// Metadata update/reset endpoints. All routes live under /api/enrichment/ — edits are
// non-destructive overrides (canonical server data is preserved; only display fields change).

// MARK: - Request bodies

/// One field of a metadata update: a new value, or `clear`, which sends JSON `null` and removes
/// the override so the original value shows again. A field left `nil` is not sent at all.
enum MetadataEdit<Value: Encodable & Sendable & Equatable>: Encodable, Sendable, Equatable {
    case set(Value)
    case clear

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .set(let value): try c.encode(value)
        case .clear: try c.encodeNil()
        }
    }
}

/// Fields accepted by PUT /api/enrichment/artists/:id/metadata. `nil` = unchanged.
/// Genres clear with `.set([])` (the server's no-override value; it can't store `null` there).
/// `mbid` reassigns the MusicBrainz id and can't be cleared, so it is only ever set.
struct ArtistMetadataUpdate: Encodable, Sendable {
    var name: MetadataEdit<String>?
    var bio: MetadataEdit<String>?
    var genres: MetadataEdit<[String]>?
    var mbid: String?
    var heroUrl: MetadataEdit<String>?
}

/// Fields accepted by PUT /api/enrichment/albums/:id/metadata. Same rules as the artist update.
struct AlbumMetadataUpdate: Encodable, Sendable {
    var title: MetadataEdit<String>?
    var year: MetadataEdit<Int>?
    var genres: MetadataEdit<[String]>?
    var rgMbid: String?
    var coverUrl: MetadataEdit<String>?
}

/// Fields accepted by PUT /api/enrichment/tracks/:id/metadata.
/// Backend persists only `title` and `trackNo`; genres/mbid are not stored for tracks.
struct TrackMetadataUpdate: Encodable, Sendable {
    var title: MetadataEdit<String>?
    var trackNo: MetadataEdit<Int>?
}

// MARK: - Internal helpers

/// Minimal decode target for the reset endpoints, which return `{ message, artist/album/track }`.
/// Only `message` is required — other fields are ignored, keeping decode lenient.
private struct ResetResponse: Decodable { let message: String? }

// MARK: - KimaAPIClient extension

extension KimaAPIClient {

    // MARK: Update

    /// PUT /api/enrichment/artists/:id/metadata — stores non-destructive display overrides.
    /// Returns the updated Artist (includes `displayName`, `userSummary`, `hasUserOverrides`, …).
    func updateArtistMetadata(id: String, update: ArtistMetadataUpdate) async throws -> Artist {
        try await putJSON("/enrichment/artists/\(id)/metadata", body: update, authed: true)
    }

    /// PUT /api/enrichment/albums/:id/metadata — stores non-destructive display overrides.
    /// Returns the updated Album (includes `displayTitle`, `displayYear`, `hasUserOverrides`, …).
    func updateAlbumMetadata(id: String, update: AlbumMetadataUpdate) async throws -> Album {
        try await putJSON("/enrichment/albums/\(id)/metadata", body: update, authed: true)
    }

    /// PUT /api/enrichment/tracks/:id/metadata — stores title and track-number overrides.
    /// Returns the updated Track. Note: the web API client points this to /library/tracks/:id/
    /// but the live backend handler is under /enrichment/tracks/:id/metadata (verified).
    func updateTrackMetadata(id: String, update: TrackMetadataUpdate) async throws -> Track {
        try await putJSON("/enrichment/tracks/\(id)/metadata", body: update, authed: true)
    }

    // MARK: Reset (clear all user overrides)

    /// POST /api/enrichment/artists/:id/reset — reverts all artist overrides to canonical values.
    func resetArtistMetadata(id: String) async throws {
        let _: ResetResponse = try await postJSON(
            "/enrichment/artists/\(id)/reset", body: EmptyRequestBody(), authed: true
        )
    }

    /// POST /api/enrichment/albums/:id/reset — reverts all album overrides to canonical values.
    func resetAlbumMetadata(id: String) async throws {
        let _: ResetResponse = try await postJSON(
            "/enrichment/albums/\(id)/reset", body: EmptyRequestBody(), authed: true
        )
    }

    /// POST /api/enrichment/tracks/:id/reset — reverts all track overrides to canonical values.
    func resetTrackMetadata(id: String) async throws {
        let _: ResetResponse = try await postJSON(
            "/enrichment/tracks/\(id)/reset", body: EmptyRequestBody(), authed: true
        )
    }
}
