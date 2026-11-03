import Foundation
import Observation

/// View model for the Playlist Detail screen.
///
/// Owns the loaded playlist, optimistic remove/reorder, rename, and delete.
@MainActor
@Observable
final class PlaylistDetailViewModel {

    // MARK: - State

    var playlist: PlaylistDetail? = nil
    var isLoading = false
    var errorMessage: String? = nil

    /// Frequency-sorted, de-duplicated cover IDs, recomputed only when the item set changes.
    private(set) var coverIds: [String] = []

    /// Rename flow.
    var isRenaming = false
    var editName = ""

    /// The share link made on this page, so the menu can offer to turn it off.
    private(set) var shareToken: String?
    /// True while the reverse-order change is being saved (stops a double tap).
    private(set) var isReversing = false
    /// True while a share link is being made (stops a double tap).
    private(set) var isCreatingShareLink = false

    // MARK: - Load

    func load(id: String, using client: KimaAPIClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            playlist = try await client.getPlaylist(id: id)
            coverIds = playlistMosaicCoverIds(from: playlist?.items)
        } catch {
            if Task.isCancelled { return }
            errorMessage = "couldn't load playlist"
        }
    }

    /// Re-fetches in place. False when it failed (the old list stays).
    @discardableResult
    func reload(id: String, using client: KimaAPIClient) async -> Bool {
        do {
            playlist = try await client.getPlaylist(id: id)
            coverIds = playlistMosaicCoverIds(from: playlist?.items)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Playback helpers

    /// Converts `PlaylistItem` array to `[Track]` for the player.
    func tracks(from items: [PlaylistItem]) -> [Track] {
        items.map(\.asTrack)
    }

    // MARK: - Remove track

    func removeTrack(trackId: String, playlistId: String, using client: KimaAPIClient, toast: ToastCenter) async {
        // Optimistic removal
        if var items = playlist?.items {
            items.removeAll { $0.track.id == trackId }
            patchItems(items)
        }
        do {
            try await client.removeTrackFromPlaylist(playlistId: playlistId, trackId: trackId)
        } catch {
            // Re-load to restore correct state on failure.
            toast.show("couldn't remove that song", style: .error)
            await reload(id: playlistId, using: client)
        }
    }

    // MARK: - Reorder

    /// Called from `.onMove`. Persists the drag with PATCH /playlists/:id/items/:itemId/move.
    /// Optimistic: the local order is applied first; on failure the previous order is restored and a toast explains.
    /// A drag can move several items (multi-select in edit mode): one PATCH per moved item, in final order, each
    /// placed after the item now before it (or at the front), so earlier moves never invalidate later anchors.
    func moveTrack(
        from source: IndexSet, to destination: Int,
        playlistId: String, using client: KimaAPIClient, toast: ToastCenter? = nil
    ) async {
        guard let original = playlist?.items, !source.isEmpty else { return }

        var moved = original
        moved.move(fromOffsets: source, toOffset: destination)

        // Item IDs involved in the drag, in their ORIGINAL relative order (IndexSet is sorted).
        let movedIDs = Set(source.map { original[$0].id })
        guard !movedIDs.isEmpty else { return }

        // Optimistic UI update.
        patchItems(moved)

        do {
            for move in Self.storedMoves(shown: moved, movedIDs: movedIDs, reversed: playlist?.reverseOrder == true) {
                try await client.movePlaylistItem(
                    playlistId: playlistId, itemId: move.itemId, afterItemId: move.afterItemId
                )
            }
        } catch {
            // A mid-sequence failure means earlier PATCHes of this drag already changed the
            // server: rolling back to the local pre-drag snapshot would diverge UI from
            // server. Ask the server instead — refetch the authoritative order.
            await reload(id: playlistId, using: client)
            toast?.show("couldn't save the new order", style: .error)
        }
    }

    /// The server's moves for a drag that left the list as `shown`: one per moved item, in final stored order, each
    /// placed after the item now before it in stored order (nil = the front), so earlier moves never invalidate later
    /// anchors. A reversed playlist is shown opposite to how it is stored, so the anchors are read from the reversed list.
    nonisolated static func storedMoves(
        shown: [PlaylistItem], movedIDs: Set<String>, reversed: Bool
    ) -> [(itemId: String, afterItemId: String?)] {
        let stored = reversed ? Array(shown.reversed()) : shown
        return stored.enumerated()
            .filter { movedIDs.contains($0.element.id) }
            .map { (itemId: $0.element.id, afterItemId: $0.offset > 0 ? stored[$0.offset - 1].id : nil) }
    }

    // MARK: - Reverse order

    /// Flips the playlist between stored order and newest-first. Optimistic; restored with a toast on failure.
    func toggleReverse(playlistId: String, using client: KimaAPIClient, toast: ToastCenter) async {
        guard let p = playlist, !isReversing else { return }
        isReversing = true
        defer { isReversing = false }
        let reversed = p.reverseOrder != true
        playlist?.reverseOrder = reversed
        playlist?.items = p.items.map { Array($0.reversed()) }
        coverIds = playlistMosaicCoverIds(from: playlist?.items)
        do {
            try await client.setPlaylistReverseOrder(id: playlistId, reversed: reversed)
        } catch {
            // Ask the server for the real state rather than restoring a snapshot an edit may have outdated.
            if await !reload(id: playlistId, using: client) {
                playlist?.reverseOrder = p.reverseOrder
                playlist?.items = p.items
                coverIds = playlistMosaicCoverIds(from: p.items)
            }
            toast.show("couldn't change the playlist order", style: .error)
        }
    }

    // MARK: - Rename

    func beginRename() {
        editName = playlist?.name ?? ""
        isRenaming = true
    }

    func saveRename(playlistId: String, using client: KimaAPIClient, toast: ToastCenter) async {
        let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        // No-op rename (empty or unchanged) — just close the editor.
        guard !trimmed.isEmpty, trimmed != playlist?.name else {
            isRenaming = false
            return
        }
        do {
            let updated = try await client.updatePlaylist(id: playlistId, name: trimmed)
            patchName(updated.name)
            isRenaming = false
            toast.show("renamed to \(updated.name.lowercased())", style: .success)
        } catch {
            // Keep the rename field open so the user can retry their edit.
            isRenaming = true
            toast.show("couldn't rename playlist", style: .error)
        }
    }

    // MARK: - Toggle public

    func togglePublic(playlistId: String, using client: KimaAPIClient, toast: ToastCenter) async {
        guard let current = playlist?.isPublic else { return }
        do {
            _ = try await client.updatePlaylist(id: playlistId, isPublic: !current)
            patchPublic(!current)
            toast.show(current ? "playlist is private" : "playlist is public", style: .success)
        } catch {
            toast.show("couldn't change who can see this playlist", style: .error)
        }
    }

    // MARK: - Share link

    /// Makes (or gets back) the playlist's share link and returns its web address; nil after an error toast.
    func shareLink(playlistId: String, using client: KimaAPIClient, toast: ToastCenter) async -> URL? {
        guard !isCreatingShareLink else { return nil }
        isCreatingShareLink = true
        defer { isCreatingShareLink = false }
        do {
            let link = try await client.createShareLink(entityType: "playlist", entityId: playlistId)
            shareToken = link.token
            return client.shareLinkURL(token: link.token)
        } catch {
            toast.show("couldn't make a share link", style: .error)
            return nil
        }
    }

    /// Turns off the share link made on this page; the old address stops working.
    func revokeShareLink(using client: KimaAPIClient, toast: ToastCenter) async {
        guard let token = shareToken else { return }
        do {
            try await client.revokeShareLink(token: token)
            shareToken = nil
            toast.show("share link turned off", style: .success)
        } catch {
            toast.show("couldn't turn off the share link", style: .error)
        }
    }

    // MARK: - Hide / unhide

    func toggleHide(playlistId: String, using client: KimaAPIClient, toast: ToastCenter) async -> Bool {
        guard let p = playlist else { return false }
        let shouldHide = p.isHidden != true
        do {
            if shouldHide {
                try await client.hidePlaylist(id: playlistId)
            } else {
                try await client.unhidePlaylist(id: playlistId)
            }
            patchHidden(shouldHide)
            if !shouldHide { toast.show("shown in playlists again", style: .success) }
            return shouldHide  // true = just hidden (caller pops on hide and offers undo)
        } catch {
            toast.show(
                shouldHide ? "couldn't hide playlist" : "couldn't unhide playlist",
                style: .error
            )
            return false
        }
    }

    // MARK: - Delete

    func delete(playlistId: String, using client: KimaAPIClient) async throws {
        try await client.deletePlaylist(id: playlistId)
    }

    // MARK: - Patch helpers (avoid full decode round-trip)

    private func patchItems(_ items: [PlaylistItem]) {
        playlist?.items = items
        playlist?.trackCount = items.count
        coverIds = playlistMosaicCoverIds(from: items)
    }

    private func patchName(_ name: String) { playlist?.name = name }

    private func patchPublic(_ isPublic: Bool) { playlist?.isPublic = isPublic }

    private func patchHidden(_ isHidden: Bool) { playlist?.isHidden = isHidden }
}
