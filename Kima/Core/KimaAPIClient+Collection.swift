import Foundation

// Paginated library queries (limit/offset) for the Collection screen. The non-paginated
// variants in KimaAPIClient+Library.swift stay for AlbumDetail and ArtistDetail.
// Only artists supports a server `query` (ILIKE); albums and tracks are filtered client-side
// in CollectionViewModel. Responses carry `total`, `offset`, `limit`.

extension KimaAPIClient {

    // MARK: - Paginated Artists

    /// GET /api/library/artists — paginated artist list with optional filter, sort and text search.
    /// `filter`: "owned" | "discovery" | "all". `sortBy`: "name" | "name-desc" | "tracks". `offset` is zero-based
    /// ((page - 1) × limit); `query` is a server-side ILIKE match on artist name.
    func getLibraryArtists(
        filter: String? = nil,
        sortBy: String? = nil,
        limit: Int = 40,
        offset: Int = 0,
        query: String? = nil
    ) async throws -> ArtistsResponse {
        var params: [String: String] = [
            "limit": "\(limit)",
            "offset": "\(offset)"
        ]
        if let filter { params["filter"] = filter }
        if let sortBy { params["sortBy"] = sortBy }
        if let query, !query.isEmpty { params["query"] = query }
        return try await get("/library/artists", query: params, authed: true)
    }

    // MARK: - Paginated Albums

    /// GET /api/library/albums — paginated album list with optional filter and sort.
    /// `filter`: "owned" | "discovery" | "all". `sortBy`: "name" | "name-desc" | "recent". `offset` is zero-based.
    func getLibraryAlbums(
        filter: String? = nil,
        sortBy: String? = nil,
        limit: Int = 40,
        offset: Int = 0
    ) async throws -> AlbumsResponse {
        var params: [String: String] = [
            "limit": "\(limit)",
            "offset": "\(offset)"
        ]
        if let filter { params["filter"] = filter }
        if let sortBy { params["sortBy"] = sortBy }
        return try await get("/library/albums", query: params, authed: true)
    }

    // MARK: - Paginated Tracks

    /// GET /api/library/tracks — paginated track list. The filter is always "owned" (no filter UI).
    /// `sortBy`: "name" | "name-desc". `offset` is zero-based.
    func getLibraryTracks(
        sortBy: String? = nil,
        limit: Int = 40,
        offset: Int = 0
    ) async throws -> TracksResponse {
        var params: [String: String] = [
            "limit": "\(limit)",
            "offset": "\(offset)"
        ]
        if let sortBy { params["sortBy"] = sortBy }
        return try await get("/library/tracks", query: params, authed: true)
    }
}
