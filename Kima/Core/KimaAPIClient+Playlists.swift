import Foundation

// Playlist CRUD + track-management methods for KimaAPIClient.
// All responses decoded into PlaylistModels.swift types.

extension KimaAPIClient {

    // MARK: - List + Detail

    /// GET /playlists — the user's playlists (owned + public/shared), with 4-item mosaic data.
    /// Server computes `trackCount`, `isOwner`, and `isHidden` inline.
    func getPlaylists() async throws -> [PlaylistSummary] {
        try await get("/playlists", authed: true)
    }

    /// GET /playlists/:id — full playlist detail with all items (sorted by `sort`).
    /// Server aliases `track.album.coverUrl` → `track.album.coverArt` on each item.
    func getPlaylist(id: String) async throws -> PlaylistDetail {
        try await get("/playlists/\(id)", authed: true)
    }

    // MARK: - Create / Update / Delete

    /// POST /playlists — create a new playlist. Returns the minimal new-playlist shape.
    func createPlaylist(name: String, isPublic: Bool = false) async throws -> PlaylistMutationResponse {
        let body = CreatePlaylistBody(name: name, isPublic: isPublic)
        return try await postJSON("/playlists", body: body, authed: true)
    }

    /// PUT /playlists/:id — rename and/or toggle public. Pass only the fields you want to change.
    /// Returns the updated playlist shape (without items).
    func updatePlaylist(
        id: String,
        name: String? = nil,
        isPublic: Bool? = nil
    ) async throws -> PlaylistMutationResponse {
        let body = UpdatePlaylistBody(name: name, isPublic: isPublic)
        return try await putJSON("/playlists/\(id)", body: body, authed: true)
    }

    /// PATCH /playlists/:id { reverseOrder } — show the playlist in reverse of its stored order (owner only).
    func setPlaylistReverseOrder(id: String, reversed: Bool) async throws {
        let _: PlaylistMutationResponse = try await patchJSON(
            "/playlists/\(KimaServer.pathSegment(id))", body: UpdatePlaylistBody(reverseOrder: reversed), authed: true
        )
    }

    /// DELETE /playlists/:id — permanently delete a playlist. Only the owner may delete.
    func deletePlaylist(id: String) async throws {
        try await deleteChecked("/playlists/\(id)", authed: true)
    }

    // MARK: - Track management

    /// POST /playlists/:id/items/batch — add up to 500 tracks in one request, appended in the given order.
    /// Callers with more than 500 tracks must send ≤500-item chunks in order (see `PlaylistPickerSheet`); order is
    /// only guaranteed within one call. Errors: 404 unknown playlist, 403 not owner, 400 bad body.
    func addTracksToPlaylist(playlistId: String, trackIds: [String]) async throws -> BatchAddTracksResponse {
        let body = BatchAddTracksBody(trackIds: trackIds)
        return try await postJSON("/playlists/\(playlistId)/items/batch", body: body, authed: true)
    }

    /// DELETE /playlists/:id/items/:trackId — remove a track by its track ID (not item ID).
    func removeTrackFromPlaylist(playlistId: String, trackId: String) async throws {
        try await deleteChecked("/playlists/\(playlistId)/items/\(trackId)", authed: true)
    }

    /// PATCH /playlists/:id/items/:itemId/move — move one item (by item ID, not track ID) directly after
    /// `afterItemId`, or to the front when nil. Response: `{ success, rank }`. Batch drags send one PATCH per item.
    /// Errors: 400 bad body or unknown anchor, 404 item not in playlist, 403 not owner.
    func movePlaylistItem(
        playlistId: String, itemId: String, afterItemId: String?
    ) async throws {
        let body = MovePlaylistItemBody(afterItemId: afterItemId)
        let _: PlaylistMoveItemResponse = try await patchJSON(
            "/playlists/\(playlistId)/items/\(itemId)/move", body: body, authed: true
        )
    }

    // MARK: - Visibility

    /// POST /playlists/:id/hide — hide a playlist from the user's library view.
    /// Works for both owned and shared (public) playlists.
    func hidePlaylist(id: String) async throws {
        let _: PlaylistMessageResponse = try await postJSON(
            "/playlists/\(id)/hide", body: EmptyRequestBody(), authed: true
        )
    }

    /// DELETE /playlists/:id/hide — unhide a previously-hidden playlist.
    func unhidePlaylist(id: String) async throws {
        try await deleteChecked("/playlists/\(id)/hide", authed: true)
    }
}

// MARK: - Private response / body helpers

/// Generic message-only response (used for hide).
private struct PlaylistMessageResponse: Decodable {
    let message: String
}

/// PATCH /playlists/:id/items/:itemId/move body. `afterItemId = nil` encodes JSON `null` = move to front.
private struct MovePlaylistItemBody: Encodable {
    let afterItemId: String?
}

/// PATCH /playlists/:id/items/:itemId/move response.
private struct PlaylistMoveItemResponse: Decodable {
    let success: Bool
    let rank: String?
}

