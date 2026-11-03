import Foundation

// Library-read methods for KimaAPIClient. Kept in a separate file so the Core networking
// plumbing stays small while each feature area adds its own extension.
// Relies on `get` being internal (not private) — see the visibility note in KimaAPIClient.swift.

// MARK: - Response envelopes for Home rails

/// Response envelope for GET /api/library/recently-listened.
/// Server returns `{ items: [...] }` with mixed entity types.
private struct RecentlyListenedResponse: Codable, Sendable {
    let items: [RecentlyListenedItem]
}

/// Response envelope for GET /api/library/tracks/:id/waveform.
/// `peaks` is an array of normalized amplitude values (0.0–1.0), start→end.
/// `count` is the number of peak samples (matches peaks.count on a well-formed response).
private struct WaveformResponse: Codable, Sendable {
    let peaks: [Double]
    let count: Int
}

extension KimaAPIClient {

    // MARK: - Discovery (non-library artists via MBID or name)

    /// GET /api/artists/discover/:nameOrMbid — artist metadata from the discovery index.
    /// Fallback when `getArtist(id:)` fails (e.g. a similar artist not yet in the library). The returned `Artist`
    /// has a UUID-format id, which marks discovery origin.
    func getArtistDiscovery(nameOrMbid: String) async throws -> Artist {
        let encoded = KimaServer.pathSegment(nameOrMbid)
        return try await get("/artists/discover/\(encoded)", authed: true)
    }

    // MARK: - Radio

    /// GET /api/library/radio?type=artist&value={id}&limit={n} — artist radio track list.
    ///
    /// Returns up to `limit` tracks seeded from the artist's similarity graph.
    /// Only meaningful for library artists (numeric id); discovery artists return an empty list.
    func getRadioTracks(type: String, value: String?, limit: Int = 100) async throws -> [Track] {
        try await getRadioPage(type: type, value: value, limit: limit).tracks
    }

    /// GET /api/library/radio — one batch of a station. `seed` and `offset` page through the server's
    /// own order (mood, wildcard, workout): `next` is the offset to ask from next, with the same seed;
    /// the server rejects an offset without a seed. `tz` lets the late-night station read the
    /// listener's evening plays in their own time zone.
    func getRadioPage(
        type: String,
        value: String?,
        limit: Int = 100,
        seed: String? = nil,
        offset: Int? = nil,
        tz: String? = nil
    ) async throws -> RadioPage {
        var query: [String: String] = ["type": type, "limit": "\(limit)"]
        if let value { query["value"] = value }
        if let seed { query["seed"] = seed }
        if let offset { query["offset"] = "\(offset)" }
        if let tz { query["tz"] = tz }
        return try await get("/library/radio", query: query, authed: true)
    }

    // MARK: - Artists

    /// GET /api/library/artists/:id — full artist with albums + topTracks. Returns a bare Artist (not wrapped).
    func getArtist(id: String) async throws -> Artist {
        try await get("/library/artists/\(id)", authed: true)
    }

    /// GET /api/library/artists/:id/play-tracks — the ordered play queue for one artist in one small
    /// response. Use this to start playback: `getArtist(id:)` returns the whole artist page (about 1 MB
    /// and 180 ms for an artist with 101 albums). The server orders the queue; pass `tracks` to the
    /// player as-is.
    func getArtistPlayTracks(id: String) async throws -> ArtistPlayTracksResponse {
        try await get("/library/artists/\(id)/play-tracks", authed: true)
    }

    // MARK: - Albums

    /// GET /api/library/albums/:id — full album with tracks + similarAlbums. Returns a bare Album (not wrapped).
    func getAlbum(id: String) async throws -> Album {
        try await get("/library/albums/\(id)", authed: true)
    }

    /// GET /api/artists/album/:rgMbid — discovery album detail by release-group MBID.
    /// Used as fallback when `getAlbum(id:)` fails.
    func getAlbumDiscovery(rgMbid: String) async throws -> Album {
        try await get("/artists/album/\(rgMbid)", authed: true)
    }

    // MARK: - Tracks

    /// GET /api/library/tracks/:id — single track. Returns a bare Track (not wrapped).
    func getTrack(id: String) async throws -> Track {
        try await get("/library/tracks/\(id)", authed: true)
    }

    /// GET /api/library/tracks/shuffle — server-shuffled track sample. Server returns `{ tracks, total }`.
    func getShuffledTracks(limit: Int? = nil) async throws -> [Track] {
        var query: [String: String] = [:]
        if let limit { query["limit"] = "\(limit)" }
        let response: TracksResponse = try await get("/library/tracks/shuffle", query: query, authed: true)
        return response.tracks
    }

    // MARK: - Home rails

    /// GET /api/library/recently-added — artists recently added to the library, decoded via
    /// `ArtistsResponse { artists: [...] }`, the same envelope as `/library/artists`.
    func getRecentlyAdded(limit: Int = 12) async throws -> [Artist] {
        let query: [String: String] = ["limit": "\(limit)"]
        let response: ArtistsResponse = try await get("/library/recently-added", query: query, authed: true)
        return response.artists
    }

    /// GET /api/library/recently-listened — mixed items (artists/podcasts/audiobooks) from `{ items: [...] }`.
    /// Throws `APIError.decoding` if the shape differs; HomeViewModel catches it and omits the rail.
    func getRecentlyListened(limit: Int = 10) async throws -> [RecentlyListenedItem] {
        let query: [String: String] = ["limit": "\(limit)"]
        let response: RecentlyListenedResponse = try await get("/library/recently-listened", query: query, authed: true)
        return response.items
    }

    // MARK: - Lyrics

    /// GET /api/library/tracks/:id/lyrics. `syncedLyrics` is an LRC string and `plainLyrics` a plain-text fallback;
    /// both may be nil. Callers treat nil or empty as "no lyrics", not an error.
    func getLyrics(trackId: String) async throws -> LyricsResponse {
        try await get("/library/tracks/\(trackId)/lyrics", authed: true)
    }

    // MARK: - Waveform

    /// GET /api/library/tracks/:id/waveform → `{ peaks, count }`: amplitude peaks normalized 0–1, start to end
    /// (about 400 values). Errors (404, bad shape, count mismatch) propagate to the caller, who decides the
    /// fallback; FullPlayerView uses `try?` and shows a flat-line scrubber.
    func getWaveform(trackId: String) async throws -> [Double] {
        let response: WaveformResponse = try await get(
            "/library/tracks/\(trackId)/waveform",
            authed: true
        )
        // Clamp defensively: the contract says 0–1, but be resilient against server drift.
        return response.peaks.map { max(0.0, min(1.0, $0)) }
    }
}
