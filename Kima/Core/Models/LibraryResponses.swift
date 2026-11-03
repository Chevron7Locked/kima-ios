import Foundation

// List-response envelopes for the library endpoints. Arrays sit under a named key (`artists`, `albums`,
// `tracks`). Single-entity endpoints return a bare entity. A row that fails to decode is dropped, not the page.

/// Envelope for GET /api/library/artists.
struct ArtistsResponse: Codable, Sendable {
    let artists: [Artist]
    let total: Int?
    let offset: Int?
    let limit: Int?
}

/// Envelope for GET /api/library/albums.
struct AlbumsResponse: Codable, Sendable {
    let albums: [Album]
    let total: Int?
    let offset: Int?
    let limit: Int?
}

/// Envelope for GET /api/library/tracks and GET /api/library/tracks/shuffle (both `{ tracks, total }`).
struct TracksResponse: Codable, Sendable {
    let tracks: [Track]
    let total: Int?
    let offset: Int?
    let limit: Int?
}

/// Envelope for GET /api/library/artists/:id/play-tracks — the ordered play queue for one artist.
///
/// The lean answer to a play tap: no audioFeatures, no MusicBrainz discography, no album fields the
/// player never reads. `getArtist` answers the same tap with 1,012,720 bytes for an artist with 101
/// albums; this returns the same queue in a few kilobytes.
///
/// The server owns the order — owned albums by effective year (`displayYear ?? year`, missing last)
/// descending, title ascending as the tie-break, then disc number (untagged disc counts as disc one)
/// and track number — so clients consume it as given. `artist` carries the name so a failed tap can
/// be labelled without fetching the artist page first.
struct ArtistPlayTracksResponse: Codable, Sendable {
    struct ArtistRef: Codable, Sendable {
        let id: String
        let name: String
    }
    let artist: ArtistRef
    let tracks: [Track]
}

/// The `total`/`offset`/`limit` paging fields shared by all three list envelopes.
private func decodePaging<K: CodingKey>(_ c: KeyedDecodingContainer<K>) throws -> (total: Int?, offset: Int?, limit: Int?) {
    guard let totalKey = K(stringValue: "total"),
          let offsetKey = K(stringValue: "offset"),
          let limitKey = K(stringValue: "limit")
    else {
        throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath,
                                                debugDescription: "envelope is missing a paging key"))
    }
    return (try c.decodeIfPresent(Int.self, forKey: totalKey),
            try c.decodeIfPresent(Int.self, forKey: offsetKey),
            try c.decodeIfPresent(Int.self, forKey: limitKey))
}

extension ArtistsResponse {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artists = try c.decodeLossyList(Artist.self, forKey: .artists)
        (total, offset, limit) = try decodePaging(c)
    }
}

extension AlbumsResponse {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albums = try c.decodeLossyList(Album.self, forKey: .albums)
        (total, offset, limit) = try decodePaging(c)
    }
}

extension TracksResponse {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try c.decodeLossyList(Track.self, forKey: .tracks)
        (total, offset, limit) = try decodePaging(c)
    }
}

extension ArtistPlayTracksResponse {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist = try c.decode(ArtistRef.self, forKey: .artist)
        tracks = try c.decodeLossyList(Track.self, forKey: .tracks)
    }
}
