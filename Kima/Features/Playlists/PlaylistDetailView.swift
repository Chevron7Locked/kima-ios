import SwiftUI

// MARK: - PlaylistDetailView

/// Playlist detail (web /playlist/[id]): hero, action bar (play, shuffle, and a "•••" menu for sharing,
/// visibility, rename and delete), and PlaylistDetailTrackList. Pushed via LibraryRoute.playlistDetail(id:).
struct PlaylistDetailView: View {
    let playlistId: String
    @Binding var path: [LibraryRoute]

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast

    @State private var vm = PlaylistDetailViewModel()
    /// The share link's web address while the share sheet is open.
    @State private var shareURL: URL?
    @State private var confirmingDelete = false
    @State private var heroHeight: CGFloat = 0

    var body: some View {
        ZStack {
            KimaScreenGround()
            if let playlist = vm.playlist {
                content(playlist: playlist)
                    .kimaReadableWidth()
                    // The list keeps to the column; its hero backdrop draws past it to the screen edges.
                    .scrollClipDisabled(KimaLayout.columnBleed(viewport: env.viewportWidth) > 0)
                    .frame(maxWidth: .infinity)
            } else if let message = vm.errorMessage, !vm.isLoading {
                KimaErrorState(message: message) { Task { await vm.load(id: playlistId, using: env.client) } }
            } else {
                KimaLoadingState { Task { await vm.load(id: playlistId, using: env.client) } }
            }
        }
        // System back button in a transparent bar, like the album, artist and radio pages.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        // Rename alert
        .alert("rename playlist", isPresented: $vm.isRenaming) {
            TextField("name", text: $vm.editName)
                .autocorrectionDisabled()
            Button("save") {
                Task { await vm.saveRename(playlistId: playlistId, using: env.client, toast: toast) }
            }
            Button("cancel", role: .cancel) { vm.isRenaming = false }
        }
        .kimaShareSheet(url: $shareURL)
        .task { await vm.load(id: playlistId, using: env.client) }
        .refreshable {
            if await !vm.reload(id: playlistId, using: env.client) {
                toast.show("couldn't refresh playlist", style: .error)
            }
        }
    }

    // MARK: - Main content

    private func content(playlist: PlaylistDetail) -> some View {
        KimaTopInsetReader { topInset in
            PlaylistDetailTrackList(
                playlist: playlist,
                player: player,
                onRemove: { trackId in
                    Task { await vm.removeTrack(trackId: trackId, playlistId: playlistId, using: env.client, toast: toast) }
                },
                onMove: { source, dest in
                    Task { await vm.moveTrack(from: source, to: dest, playlistId: playlistId, using: env.client, toast: toast) }
                },
                onAddToPlaylist: { track in
                    env.playlistPicker.present(.tracks([track]))
                },
                buildTracks: { vm.tracks(from: $0) }
            ) {
                VStack(spacing: 0) {
                    heroSection(playlist: playlist, topSafeInset: topInset)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }
                    actionBar(playlist: playlist)
                }
            }
            // A faint violet wash in the fade, subtle enough not to fight the mosaic.
            .kimaHeroGround(heroHeight: heroHeight, columnBleed: true) {
                KimaHeroArtBackdrop(
                    imageURL: vm.coverIds.first.flatMap { CoverArtURL.url(base: env.server, coverId: $0, size: 512) },
                    wash: KimaColor.ambient.opacity(0.16))
            }
        }
    }

    // MARK: - Menu actions

    private func delete() async {
        do {
            try await vm.delete(playlistId: playlistId, using: env.client)
            path.removeLast()
            toast.show("playlist deleted", style: .success)
        } catch {
            toast.show("couldn't delete playlist", style: .error)
        }
    }

    /// Hiding leaves the page (as on the web) and offers undo; showing it again stays.
    private func toggleHidden() async {
        guard await vm.toggleHide(playlistId: playlistId, using: env.client, toast: toast) else { return }
        path.removeLast()
        let client = env.client, id = playlistId, toast = toast
        toast.show("hidden from playlists", style: .success, action: ToastAction(label: "undo") {
            Task {
                do {
                    try await client.unhidePlaylist(id: id)
                    toast.show("shown in playlists again", style: .success)
                } catch {
                    toast.show("couldn't show the playlist again", style: .error)
                }
            }
        })
    }

    // MARK: - Hero section

    private func heroSection(playlist: PlaylistDetail, topSafeInset: CGFloat) -> some View {
        KimaDetailHero(topInset: topSafeInset) {
            PlaylistMosaicView(coverIds: vm.coverIds, cellSize: 100)
        } info: {
            // Who can see it: another user's playlist reaches you only when public.
            KimaKicker(title: playlist.isOwner != true || playlist.isPublic == true ? "public playlist" : "private playlist")

            // Name — tap to rename (owner only)
            if playlist.isOwner == true {
                KimaDetailHeroTitle(text: playlist.name)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.beginRename() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("renames the playlist")
            } else {
                KimaDetailHeroTitle(text: playlist.name)
            }

            if let user = playlist.user, playlist.isOwner != true {
                KimaDetailHeroByline(text: user.username)
            }
            let songCount = playlist.trackCount ?? playlist.items?.count ?? 0
            KimaDetailHeroMeta(parts: ["\(songCount) \(songCount == 1 ? "song" : "songs")"])
        }
    }

    // MARK: - Action bar

    private func actionBar(playlist: PlaylistDetail) -> some View {
        let items = playlist.items ?? []
        return HStack(spacing: KimaSpacing.md) {
            // Play
            if !items.isEmpty {
                KimaHeroPlayButton(label: "play all") {
                    player.play(tracks: vm.tracks(from: items), startAt: 0)
                }
                .accessibilityIdentifier("playlist-play-all")   // leaf button — UITest: play-all → artist hydration
            }

            // Shuffle
            if items.count > 1 {
                KimaActionPill(title: "shuffle", systemImage: "shuffle") {
                    player.play(tracks: vm.tracks(from: items).shuffled(), startAt: 0)
                }
            }

            // Reverse order (owner only): newest additions first, saved on the server for every device.
            if playlist.isOwner == true, items.count > 1 {
                let reversed = playlist.reverseOrder == true
                KimaIconDiscButton(
                    systemName: "arrow.up.arrow.down", glyphSize: 14,
                    label: "reverse order", isLoading: vm.isReversing, isOn: reversed
                ) {
                    Task { await vm.toggleReverse(playlistId: playlistId, using: env.client, toast: toast) }
                }
            }

            Spacer(minLength: 0)

            PlaylistActionsMenu(
                playlist: playlist,
                hasShareLink: vm.shareToken != nil,
                isWorking: vm.isCreatingShareLink,
                onTogglePublic: {
                    Task { await vm.togglePublic(playlistId: playlistId, using: env.client, toast: toast) }
                },
                onShare: {
                    Task { shareURL = await vm.shareLink(playlistId: playlistId, using: env.client, toast: toast) }
                },
                onStopSharing: { Task { await vm.revokeShareLink(using: env.client, toast: toast) } },
                onToggleHidden: { Task { await toggleHidden() } },
                onRename: { vm.beginRename() },
                onDelete: { confirmingDelete = true }
            )
            // On the ••• menu, so the popover points at it.
            .confirmationDialog("delete playlist?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("delete", role: .destructive) { Task { await delete() } }
                Button("cancel", role: .cancel) {}
            } message: {
                Text("deletes \u{201C}\(playlist.name.lowercased())\u{201D} for everyone. this can't be undone.")
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.md)
    }
}
