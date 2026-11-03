import Foundation

// MARK: - KimaAPIClient + Search

extension KimaAPIClient {

    /// GET /api/search/?q=\(query)&type=all&limit=\(limit)
    ///
    /// Unified library search across artists, albums, tracks, podcasts, audiobooks,
    /// and episodes. Results are transformed by the backend to standard library shapes.
    func searchLibrary(query: String, type: String = "all", limit: Int = 20) async throws -> SearchResults {
        let n = min(max(limit, 1), 100)
        return try await get(
            "/search",
            query: ["q": query, "type": type, "limit": String(n)],
            authed: true
        )
    }

    /// GET /api/search/discover?q=…&type=podcasts — podcast discover search for `PodcastAddView`. Returns
    /// `DiscoverPodcastResult` with feedUrl, genres and trackCount, which `type=all` lacks. Server caches 15 minutes.
    func searchDiscover(query: String, type: String = "podcasts") async throws -> [DiscoverPodcastResult] {
        struct Envelope: Decodable, Sendable { let results: [DiscoverPodcastResult] }
        let resp: Envelope = try await get(
            "/search/discover",
            query: ["q": query, "type": type],
            authed: true
        )
        return resp.results
    }

    /// GET /api/search/discover?q=…&type=all&limit=… — external discovery (Last.fm + iTunes + Deezer): a mixed array
    /// of artists, tracks and podcasts plus an optional alias correction. Server caches 15 minutes. Callers should
    /// require a query of at least 2 characters.
    func searchDiscoverAll(query: String, limit: Int = 20) async throws -> DiscoverAllResponse {
        let n = min(max(limit, 1), 100)
        return try await get(
            "/search/discover",
            query: ["q": query, "type": "all", "limit": String(n)],
            authed: true
        )
    }

    /// GET /api/search/discover/similar?artist=…&mbid=… — Last.fm similar artists as `DiscoverResult` items with
    /// `type == .music`. Fires after `searchDiscoverAll` resolves a top music artist.
    func searchDiscoverSimilar(artist: String, mbid: String) async throws -> [DiscoverResult] {
        struct Response: Decodable, Sendable { let similarArtists: [DiscoverResult] }
        let resp: Response = try await get(
            "/search/discover/similar",
            query: ["artist": artist, "mbid": mbid],
            authed: true
        )
        return resp.similarArtists
    }
}
