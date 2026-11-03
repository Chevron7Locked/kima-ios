import SwiftUI

// MARK: - DiscoverView
// The Discover Weekly screen as an editorial "weekly dig". Pushed from the Home banner (not a tab).
// Layout: hero masthead, action bar, then empty state OR featured pick, two featured rows, crate rows, unavailable albums, how-it-works.
// SSE discover ticks reload in place; batch status polls every 3 s while building.

struct DiscoverView: View {

    @Environment(AppEnvironment.self)  private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self)     private var toast

    @State private var vm = DiscoverViewModel()
    @State private var showCancelConfirm = false
    @State private var showBuildConfirm = false

    // MARK: - Body

    var body: some View {
        content
            .task { await env.acquire.refresh(client: env.client) }
    }

    private var content: some View {
        KimaPhaseScreen(phase: vm.playlistPhase, retry: { Task { await vm.load(using: env.client) } }) {
            contentFeed
        }
        .task { await vm.load(using: env.client) }
        .onDisappear { vm.stopPolling() }
        .refreshable { await vm.load(using: env.client) }
        .onChange(of: env.events.discoverTick) { _, _ in
            Task { await vm.load(using: env.client) }
        }
        .onChange(of: vm.stoppedWatchingBuild) { _, stopped in
            guard stopped else { return }
            toast.show("still building. pull down to check again.", style: .info)
            vm.stoppedWatchingBuild = false
        }
    }

    // MARK: - Content feed

    private var contentFeed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: KimaSpacing.lg) {

                DiscoverHeroSection(playlist: vm.playlist)

                // Only when it has a control to show.
                if vm.playlist?.tracks.isEmpty == false || vm.isGenerating {
                    DiscoverActionBar(
                        playlist: vm.playlist,
                        isPlaylistPlaying: isPlaylistPlaying,
                        isPlaying: player.isPlaying,
                        isGenerating: vm.isGenerating,
                        onPlayToggle: handlePlayToggle,
                        onCancelGeneration: { showCancelConfirm = true }
                    )
                    // On the bar that holds the stop button, so the popover points at it.
                    .confirmationDialog(
                        "stop building this week's playlist?",
                        isPresented: $showCancelConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("stop", role: .destructive) {
                            Task {
                                let ok = await vm.cancelGeneration(using: env.client)
                                if !ok { toast.show("couldn't stop it. try again.", style: .error) }
                            }
                        }
                        Button("keep going", role: .cancel) {}
                    } message: {
                        Text("this stops the current build.")
                    }
                }

                if let p = vm.playlist, !p.tracks.isEmpty {
                    trackListSection(p)
                    if !p.unavailable.isEmpty { unavailableSection(p) }
                    DiscoverHowItWorks()
                } else {
                    emptyState
                }
            }
            .kimaReadableWidth()
            .frame(maxWidth: .infinity)
        }
        .kimaScrollTopGround()
        .kimaMiniPlayerClearance()
    }

    // MARK: - Track list: the weekly dig
    //
    // Featured hero pick, a few smaller featured picks, then the dense tail (DiscoverPickRows).

    private func trackListSection(_ playlist: DiscoverPlaylist) -> some View {
        let pick = playlist.featuredPick
        let rest = playlist.tracks.filter { $0.id != pick?.id }
        let featuredCount = min(2, rest.count)
        let featured = Array(rest.prefix(featuredCount))
        let tail = Array(rest.dropFirst(featuredCount))

        return VStack(alignment: .leading, spacing: 0) {
            if let pick {
                DiscoverFeaturedPick(
                    track: pick,
                    isCurrentTrack: player.currentTrack?.id == pick.id,
                    isPlaying: player.isPlaying,
                    onPlay: { handlePlayTrack(id: pick.id, in: playlist) },
                    onTogglePlay: { player.togglePlayPause() },
                    onLike: { Task { await vm.toggleLike(track: pick, using: env.client) } }
                )
                .padding(.bottom, featured.isEmpty && tail.isEmpty ? 0 : KimaSpacing.lg)
            }

            if !featured.isEmpty {
                VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                    ForEach(Array(featured.enumerated()), id: \.element.id) { i, track in
                        DiscoverFeaturedRow(
                            track: track,
                            index: i + 2,
                            isCurrentTrack: player.currentTrack?.id == track.id,
                            isPlaying: player.isPlaying,
                            onPlay: { handlePlayTrack(id: track.id, in: playlist) },
                            onTogglePlay: { player.togglePlayPause() },
                            onLike: { Task { await vm.toggleLike(track: track, using: env.client) } }
                        )
                    }
                }
                .padding(.bottom, tail.isEmpty ? 0 : KimaSpacing.sm)
            }

            if !tail.isEmpty {
                KimaSectionHeader(title: "more from this week")

                ForEach(Array(tail.enumerated()), id: \.element.id) { i, track in
                    DiscoverCrateRow(
                        track: track,
                        index: i + 2 + featured.count,
                        isCurrentTrack: player.currentTrack?.id == track.id,
                        isPlaying: player.isPlaying,
                        onPlay: { handlePlayTrack(id: track.id, in: playlist) },
                        onTogglePlay: { player.togglePlayPause() },
                        onLike: { Task { await vm.toggleLike(track: track, using: env.client) } }
                    )
                }
            }
        }
    }

    // MARK: - Unavailable albums section

    private func unavailableSection(_ playlist: DiscoverPlaylist) -> some View {
        DiscoverUnavailableSection(
            unavailable: playlist.unavailable,
            isRetrying: vm.isRetrying,
            onRetryAll: env.acquire.canAcquire ? {
                Task {
                    switch await vm.retryUnavailable(using: env.client) {
                    case .started(let msg):
                        toast.show(msg, style: .success)
                    case .noChange(let msg):
                        if let msg { toast.show(msg, style: .info) }
                    case .failed:
                        toast.show("couldn't retry. try again.", style: .error)
                    }
                }
            } : nil
        )
    }

    // MARK: - Empty state
    //
    // Stats panel (--) + 3-card explainer + Generate button.

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xl) {
            // Where things stand; the masthead above carries the page's name.
            KimaKicker(title: vm.isGenerating ? "building…" : "not built yet")

            // Stat placeholders
            HStack(spacing: KimaSpacing.sm) {
                ForEach(["tracks", "duration", "artists"], id: \.self) { label in
                    KimaStatTile(value: "--", label: label, tint: KimaColor.textFaint)
                }
            }

            // 3-card explainer (Finds / Downloads / Cleans up)
            VStack(spacing: KimaSpacing.sm) {
                explainerCard(tag: "finds",     body: "similar artists via Last.fm, grouped by similarity tier")
                explainerCard(tag: "downloads", body: "full albums to /music/discovery on your server")
                explainerCard(tag: "cleans up", body: "unliked albums are removed at the end of the week. liked ones stay.")
            }

            // Generate / in-progress button: only for a listener who may start downloads.
            if env.acquire.canAcquire {
                KimaPrimaryButton(
                    title: vm.isGenerating ? vm.progressLabel : "build this week's playlist",
                    isLoading: vm.isGenerating,
                    systemImage: vm.isGenerating ? nil : "arrow.clockwise"
                ) {
                    if !vm.isGenerating { showBuildConfirm = true }
                }
                .disabled(vm.isGenerating)
                // On the button itself, so the popover points at it.
                .confirmationDialog(
                    "build this week's playlist?",
                    isPresented: $showBuildConfirm,
                    titleVisibility: .visible
                ) {
                    Button("build it") {
                        Task {
                            let ok = await vm.generate(using: env.client)
                            toast.show(ok ? "building this week's playlist" : "couldn't start. try again.",
                                       style: ok ? .success : .error)
                        }
                    }
                    Button("cancel", role: .cancel) {}
                } message: {
                    Text("your server finds artists like the ones you play and downloads their albums. albums you haven't liked are removed at the end of the week.")
                }
            } else if env.acquire.isLocked {
                Text(AcquirePermission.lockedLabel)
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        // The feed's 16pt row gap already sits above; this tops it up to the 24pt hero gap.
        .padding(.top, KimaSpacing.sm)
        .padding(.bottom, KimaSpacing.xl)
    }

    private func explainerCard(tag: String, body: String) -> some View {
        HStack(alignment: .top, spacing: KimaSpacing.md) {
            Text(tag)
                .font(KimaType.meta)
                .foregroundStyle(KimaColor.textMuted)
                .frame(width: 72, alignment: .leading)
            Text(body)
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(KimaSpacing.md)
        .background(KimaColor.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: KimaRadius.card))
        .overlay(RoundedRectangle(cornerRadius: KimaRadius.card).strokeBorder(KimaColor.hairline, lineWidth: 1))
    }

    // MARK: - Actions

    private var isPlaylistPlaying: Bool {
        guard let p = vm.playlist else { return false }
        return p.tracks.contains { $0.id == player.currentTrack?.id }
    }

    private func handlePlayToggle() {
        if isPlaylistPlaying {
            player.togglePlayPause()
        } else {
            handlePlayPlaylist()
        }
    }

    private func handlePlayPlaylist() {
        guard let p = vm.playlist, !p.tracks.isEmpty else { return }
        player.play(tracks: makeTracks(from: p.tracks), startAt: 0)
    }

    /// Plays the crate starting at `id`'s real position in the playlist's original track
    /// order — used by the hero pick, featured rows, and crate tail alike, since each of
    /// those is a filtered subset and can't rely on its own local index.
    private func handlePlayTrack(id: String, in playlist: DiscoverPlaylist) {
        guard let index = playlist.tracks.firstIndex(where: { $0.id == id }) else { return }
        player.play(tracks: makeTracks(from: playlist.tracks), startAt: index)
    }

    /// Converts `DiscoverTrack` items into the canonical `Track` type used by PlaybackController.
    private func makeTracks(from discoverTracks: [DiscoverTrack]) -> [Track] {
        discoverTracks.map { dt in
            Track(
                id: dt.id, title: dt.title, duration: dt.duration,
                artist: TrackArtistRef(id: "", name: dt.artist),
                album: TrackAlbumRef(id: dt.albumId, title: dt.album, coverArt: dt.coverUrl)
            )
        }
    }
}
