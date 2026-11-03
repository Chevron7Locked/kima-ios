import SwiftUI

// MARK: - PlaylistPickerSheet

/// Add-to-Playlist sheet, presented app-wide from `AppShellView` off `env.playlistPicker.source`.
/// Resolves the source to track ids, then POSTs them to `/playlists/:id/items` for an existing
/// or newly created playlist.
struct PlaylistPickerSheet: View {
    let source: PlaylistAddSource

    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    /// Track IDs resolved from `source` (see `PlaylistAddSource`). Populated on appear.
    @State private var trackIds: [String] = []
    /// Albums of an artist source whose tracks couldn't be loaded (said in the add toast).
    @State private var failedAlbums = 0
    @State private var isResolving = true
    @State private var resolveFailed = false

    @State private var playlists: [PlaylistSummary] = []
    @State private var isLoadingPlaylists = true
    @State private var loadFailed = false

    /// True while an add/create network operation is in flight.
    @State private var isAdding = false

    /// Create-new-playlist alert state.
    @State private var showCreateAlert = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                KimaScreenGround()
                content
                // Topmost layer so success/error toasts render above the sheet (the app-level
                // overlay sits behind the presented sheet). Same ToastCenter, so it stays in sync.
                KimaToastOverlay()
            }
            .navigationTitle("add to playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close") { env.playlistPicker.dismiss() }
                        .foregroundStyle(KimaColor.textSecondary)
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KimaColor.base)
        .task { await resolveAndLoad() }
        .alert("new playlist", isPresented: $showCreateAlert) {
            TextField("playlist name", text: $newName)
                .autocorrectionDisabled()
            Button("create") { Task { await createAndAdd() } }
            Button("cancel", role: .cancel) { newName = "" }
        } message: {
            Text("create a playlist and add \(countLabel) to it.")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            selectionStatus
            newPlaylistButton
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.top, KimaSpacing.sm)
                .padding(.bottom, KimaSpacing.md)

            KimaHairline().padding(.horizontal, KimaSpacing.lg)

            if isLoadingPlaylists {
                KimaLoadingState { Task { await reloadPlaylists() } }
            } else if loadFailed {
                KimaErrorState(message: "couldn't load playlists") { Task { await reloadPlaylists() } }
            } else if playlists.isEmpty {
                messageState(
                    icon: "music.note.list",
                    title: "no playlists yet",
                    subtitle: "create one to get started."
                )
            } else {
                playlistList
            }
        }
    }

    private var selectionStatus: some View {
        Text(statusLabel)
            .font(KimaType.meta)
            .foregroundStyle(KimaColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.top, KimaSpacing.md)
    }

    private var statusLabel: String {
        if isResolving { return "preparing tracks…" }
        if resolveFailed { return "couldn't load tracks to add" }
        if trackIds.isEmpty { return "no tracks to add" }
        return "\(countLabel) selected"
    }

    private var newPlaylistButton: some View {
        KimaPrimaryButton(title: "new playlist", systemImage: "plus", size: .compact) {
            showCreateAlert = true
        }
        .disabled(isResolving || isAdding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playlistList: some View {
        ScrollView {
            LazyVStack(spacing: KimaSpacing.xs) {
                ForEach(playlists) { playlist in
                    PlaylistPickerRow(playlist: playlist) {
                        Task { await add(to: playlist) }
                    }
                    .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                            .strokeBorder(KimaColor.hairline, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.top, KimaSpacing.md)
            .padding(.bottom, KimaSpacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .kimaKeyboardSafeCanvas()
        .disabled(isResolving || isAdding)
        .opacity(isResolving || isAdding ? 0.45 : 1)
        .overlay { if isAdding { addingOverlay } }
    }

    // MARK: - States

    private var addingOverlay: some View {
        ZStack {
            KimaColor.base.opacity(0.35).ignoresSafeArea()
            ProgressView().tint(KimaColor.brand)
        }
    }

    private func messageState(icon: String, title: String, subtitle: String) -> some View {
        KimaEmptyState(icon: icon, title: title, message: subtitle)
    }

    // MARK: - Labels

    private var countLabel: String {
        let n = trackIds.count
        return "\(n) \(n == 1 ? "track" : "tracks")"
    }

    /// Builds the post-add toast from the batch endpoint's summary counts, e.g.
    /// "Added 12 tracks to Chill" or "Added 12 tracks to Chill (1 already there)".
    private func summaryMessage(added: Int, skippedExisting: Int, skippedInvalid: Int, name: String) -> String {
        let noun = added == 1 ? "track" : "tracks"
        var message = "added \(added) \(noun) to \(name)"
        var skipped: [String] = []
        if skippedExisting > 0 { skipped.append("\(skippedExisting) already there") }
        if skippedInvalid > 0 { skipped.append("\(skippedInvalid) invalid") }
        if !skipped.isEmpty { message += " (\(skipped.joined(separator: ", ")))" }
        if failedAlbums > 0 { message += ". \(couldntLoadAlbumsText(failedAlbums))" }
        return message
    }

    // MARK: - Load + resolve

    private func resolveAndLoad() async {
        // Show the playlist list ASAP; track resolution (which may fan out for artists) runs after.
        if let pls = await fetchPlaylists() {
            playlists = pls
            loadFailed = false
        } else {
            loadFailed = true
        }
        isLoadingPlaylists = false

        if let ids = await resolveTrackIds() {
            trackIds = ids
            resolveFailed = false
        } else {
            resolveFailed = true
        }
        isResolving = false
    }

    /// Fetches the playlist list again (the retry on the loading and error states).
    private func reloadPlaylists() async {
        isLoadingPlaylists = true
        if let pls = await fetchPlaylists() {
            playlists = pls
            loadFailed = false
        } else {
            loadFailed = true
        }
        isLoadingPlaylists = false
    }

    private func fetchPlaylists() async -> [PlaylistSummary]? {
        try? await env.client.getPlaylists()
    }

    /// Resolve `source` to a concrete, ordered list of track IDs. Returns nil on failure.
    /// Delegates to `KimaAPIClient.resolveTracks(for:)` — the single source of truth shared
    /// with every Add-to-Queue surface.
    private func resolveTrackIds() async -> [String]? {
        guard let resolved = await env.client.resolveTracks(for: source) else { return nil }
        failedAlbums = resolved.failedAlbums
        return resolved.tracks.map(\.id)
    }

    // MARK: - Add

    /// Adds `trackIds` to `playlistId` via `POST /playlists/:id/items/batch`, chunked into
    /// ≤500-track batches (the server's per-request cap) sent in order so a large
    /// add-album/add-artist collection preserves its order across chunk boundaries.
    private func batchAdd(
        trackIds: [String], to playlistId: String
    ) async throws -> (added: Int, skippedExisting: Int, skippedInvalid: Int) {
        var added = 0, skippedExisting = 0, skippedInvalid = 0
        for chunk in trackIds.chunked(into: 500) {
            let result = try await env.client.addTracksToPlaylist(playlistId: playlistId, trackIds: chunk)
            added += result.added
            skippedExisting += result.skippedExisting
            skippedInvalid += result.skippedInvalid
        }
        return (added, skippedExisting, skippedInvalid)
    }

    private func add(to playlist: PlaylistSummary) async {
        guard !isAdding else { return }
        guard !trackIds.isEmpty else {
            toast.show("no tracks to add", style: .error)
            return
        }
        isAdding = true
        do {
            let result = try await batchAdd(trackIds: trackIds, to: playlist.id)
            isAdding = false
            toast.show(
                summaryMessage(
                    added: result.added, skippedExisting: result.skippedExisting,
                    skippedInvalid: result.skippedInvalid, name: playlist.name
                ),
                style: result.added > 0 ? .success : .info
            )
            env.playlistPicker.dismiss()
        } catch {
            isAdding = false
            toast.show("couldn't add to \(playlist.name)", style: .error)
            // Keep the sheet open so the user can retry / pick another playlist.
        }
    }

    private func createAndAdd() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        newName = ""
        guard !name.isEmpty else {
            toast.show("playlist name can't be empty", style: .error)
            return
        }
        guard !isAdding else { return }
        guard !trackIds.isEmpty else {
            toast.show("no tracks to add", style: .error)
            return
        }
        isAdding = true
        do {
            let created = try await env.client.createPlaylist(name: name)
            let result = try await batchAdd(trackIds: trackIds, to: created.id)
            isAdding = false
            toast.show(
                summaryMessage(
                    added: result.added, skippedExisting: result.skippedExisting,
                    skippedInvalid: result.skippedInvalid, name: created.name
                ),
                style: result.added > 0 ? .success : .info
            )
            env.playlistPicker.dismiss()
        } catch {
            isAdding = false
            toast.show("couldn't create playlist", style: .error)
        }
    }
}
