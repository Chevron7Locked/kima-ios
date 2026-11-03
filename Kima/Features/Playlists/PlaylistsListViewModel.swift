import Foundation
import Observation

/// View model for the Playlists list screen: owns the playlist list, create/delete operations, and the visibility tab.
/// `visiblePlaylists` / `hiddenPlaylists` are computed from `playlists`; `showHiddenTab` toggles between them;
/// the inline create panel uses `isCreating`, `newPlaylistName` and `makePublic`.
@MainActor
@Observable
final class PlaylistsListViewModel {

    // MARK: - State

    var playlists: [PlaylistSummary] = []
    var isLoading = false
    var errorMessage: String? = nil

    /// Create-playlist inline panel visibility.
    var isCreating = false
    var newPlaylistName = ""
    var makePublic = false
    var isSubmitting = false
    var createError: String? = nil

    /// When true, the hidden-playlists tab is shown instead of the main list.
    var showHiddenTab = false

    // MARK: - Computed splits

    var visiblePlaylists: [PlaylistSummary] {
        playlists.filter { $0.isHidden != true }
    }

    var hiddenPlaylists: [PlaylistSummary] {
        playlists.filter { $0.isHidden == true }
    }

    var displayedPlaylists: [PlaylistSummary] {
        showHiddenTab ? hiddenPlaylists : visiblePlaylists
    }

    // MARK: - Load

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// Loads the list. A call while a load is running (pull-to-refresh during the first load)
    /// waits for that load instead of being dropped.
    func load(using client: KimaAPIClient) async {
        if let loadTask { return await loadTask.value }
        let task = Task { [weak self] in
            await self?.fetch(using: client)
            self?.loadTask = nil
        }
        loadTask = task
        await task.value
    }

    private func fetch(using client: KimaAPIClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            playlists = try await client.getPlaylists()
        } catch {
            errorMessage = "couldn't load playlists"
        }
    }

    // MARK: - Create

    func submitCreate(using client: KimaAPIClient) async -> String? {
        let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        isSubmitting = true
        createError = nil
        defer { isSubmitting = false }
        do {
            let created = try await client.createPlaylist(name: trimmed, isPublic: makePublic)
            // Optimistically prepend so it appears immediately.
            let summary = PlaylistSummary(
                id: created.id,
                name: created.name,
                isPublic: created.isPublic,
                isOwner: true,
                isHidden: false,
                user: nil,
                trackCount: 0,
                items: []
            )
            playlists.insert(summary, at: 0)
            resetCreateState()
            return created.id
        } catch {
            createError = "couldn't create playlist"
            return nil
        }
    }

    func resetCreateState() {
        isCreating = false
        newPlaylistName = ""
        makePublic = false
        createError = nil
    }

    // MARK: - Playback

    /// Playlists whose play request is in flight: their cards spin and ignore repeat taps.
    var startingIds: Set<String> = []

    /// Play a playlist's own tracks, in playlist order.
    func play(
        playlist: PlaylistSummary,
        using client: KimaAPIClient,
        player: PlaybackController,
        toast: ToastCenter
    ) async {
        guard !startingIds.contains(playlist.id) else { return }
        startingIds.insert(playlist.id)
        defer { startingIds.remove(playlist.id) }
        do {
            let detail = try await client.getPlaylist(id: playlist.id)
            let tracks = (detail.items ?? []).map(\.asTrack)
            guard !tracks.isEmpty else {
                // Every play path says why nothing started.
                toast.show("\(playlist.name) is empty", style: .error)
                return
            }
            player.play(tracks: tracks, startAt: 0)
        } catch {
            toast.show("couldn't play \(playlist.name)", style: .error)
        }
    }

    // MARK: - Visibility toggle (hide / unhide)

    func toggleHide(
        playlist: PlaylistSummary,
        using client: KimaAPIClient,
        toast: ToastCenter
    ) async {
        let shouldHide = playlist.isHidden != true
        do {
            if shouldHide {
                try await client.hidePlaylist(id: playlist.id)
            } else {
                try await client.unhidePlaylist(id: playlist.id)
            }
            // Patch local state without a full reload.
            if let idx = playlists.firstIndex(where: { $0.id == playlist.id }) {
                let p = playlists[idx]
                playlists[idx] = PlaylistSummary(
                    id: p.id, name: p.name, isPublic: p.isPublic,
                    isOwner: p.isOwner, isHidden: shouldHide,
                    user: p.user, trackCount: p.trackCount, items: p.items
                )
            }
        } catch {
            // Local state is untouched (patch runs only on success), so the row
            // stays correct — but tell the user the action didn't take.
            toast.show(
                shouldHide ? "couldn't hide playlist" : "couldn't unhide playlist",
                style: .error
            )
        }
    }
}
