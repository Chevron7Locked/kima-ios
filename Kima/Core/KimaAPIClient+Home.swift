import Foundation

// Home-section API methods for KimaAPIClient. Response shapes, where not obvious:
//   GET /api/mixes → bare [HomeMix] array (no envelope); POST /api/mixes/refresh → { message, mixes }
//   GET /api/recommendations/for-you and /api/discover/popular-artists → { artists: [...] }
//   GET /api/browse/all → { playlists, radios, genres }

extension KimaAPIClient {

    // MARK: - Mixes

    /// The listener's time zone, sent on every mix request so the night mixes read "after dark" locally.
    private static var mixQuery: [String: String] { ["tz": TimeZone.current.identifier] }

    /// GET /api/mixes?tz= → bare [HomeMix] array.
    func getMixes() async throws -> [HomeMix] {
        try await get("/mixes", query: Self.mixQuery, authed: true)
    }

    /// POST /api/mixes/refresh?tz= → { message, mixes: [HomeMix] }
    /// Returns the refreshed mix list so callers can update their phase immediately.
    @discardableResult
    func refreshMixes() async throws -> [HomeMix] {
        let response: MixesRefreshResponse = try await postJSON(
            "/mixes/refresh",
            query: Self.mixQuery,
            body: EmptyRequestBody(),
            authed: true
        )
        return response.mixes
    }

    /// GET /api/mixes/:id?tz= → { ...mix, tracks: [...] }
    /// Resolves a HomeMix's playable tracks (mix metadata from /mixes has no tracks).
    /// Album covers arrive under `coverUrl`, so tracks decode via MixTrack and convert to
    /// the app's Track with the cover populated.
    func getMixTracks(id: String) async throws -> [Track] {
        let response: MixDetailResponse = try await get("/mixes/\(KimaServer.pathSegment(id))", query: Self.mixQuery, authed: true)
        return (response.tracks ?? []).map { $0.asTrack() }
    }

    // MARK: - Recommendations

    /// GET /api/recommendations/for-you?limit=N → { artists: [Artist] }
    /// Same Artist shape as /library/artists; uses RecommendationsForYouResponse envelope.
    func getRecommendations(limit: Int = 10) async throws -> [Artist] {
        let response: RecommendationsForYouResponse = try await get(
            "/recommendations/for-you",
            query: ["limit": "\(limit)"],
            authed: true
        )
        return response.artists
    }

    // MARK: - Popular Artists

    /// GET /api/discover/popular-artists?limit=N → { artists: [HomePopularArtist] }
    /// Last.FM sourced; `id` may be nil for entries not in the local library.
    func getPopularArtists(limit: Int = 20) async throws -> [HomePopularArtist] {
        let response: PopularArtistsAPIResponse = try await get(
            "/discover/popular-artists",
            query: ["limit": "\(limit)"],
            authed: true
        )
        return response.artists
    }

    // MARK: - Browse / Featured Playlists

    /// GET /api/browse/all → extracts `.playlists` (Deezer-sourced featured playlists).
    /// Other keys (`radios`, `genres`) are decoded but discarded by BrowseAllAPIResponse.
    func getFeaturedPlaylists() async throws -> [HomePlaylistPreview] {
        let response: BrowseAllAPIResponse = try await get("/browse/all", authed: true)
        return response.playlists
    }

    /// GET /api/browse/playlists/:id → full Deezer playlist with tracks.
    /// Distinct from /api/playlists/:id (user playlists).
    func getBrowsePlaylist(id: String) async throws -> BrowsePlaylistDetail {
        try await get("/browse/playlists/\(id)", authed: true)
    }
}
