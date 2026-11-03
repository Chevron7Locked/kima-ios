import SwiftUI

// MARK: - BrowsePlaylistDetailView

/// Deezer browse playlist detail (GET /api/browse/playlists/:id): blurred hero, an action row (import the
/// playlist into your library; stop the preview while one plays), then the tracks, each tapping to a
/// 30-second preview. Pushed via LibraryRoute.browsePlaylistDetail(id:).
@MainActor
struct BrowsePlaylistDetailView: View {
    let playlistId: String

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast

    @State private var playlist: BrowsePlaylistDetail? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var previewer = ClipPreviewPlayer()
    @State private var showImport = false
    @State private var heroHeight: CGFloat = 0

    var body: some View {
        ZStack {
            KimaScreenGround()
            if let playlist {
                content(playlist: playlist)
            } else if let errorMessage, !isLoading {
                KimaErrorState(message: errorMessage) { Task { await load() } }
            } else {
                KimaLoadingState { Task { await load() } }
            }
        }
        // System back button in a transparent bar, like the other pushed screens.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .task { await load() }
    }

    // MARK: - Main content

    private func content(playlist: BrowsePlaylistDetail) -> some View {
        KimaTopInsetReader { topInset in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection(playlist: playlist, topSafeInset: topInset)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }
                    actionRow(playlist: playlist)
                    trackList(playlist: playlist)
                }
                .kimaReadableWidth()
                .frame(maxWidth: .infinity)
            }
            .kimaMiniPlayerClearance()
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(.container, edges: .top)
            .kimaHeroGround(heroHeight: heroHeight) {
                KimaHeroArtBackdrop(imageURL: playlist.imageUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) },
                                    authenticated: false)
            }
        }
        .onDisappear { previewer.stop() }
        .sheet(isPresented: $showImport) {
            ImportView(prefillURL: playlist.url).appEnvironment(env, toast)
        }
        .onChange(of: player.isPlaying) { _, isNowPlaying in
            if isNowPlaying { previewer.stop() }
        }
    }

    // MARK: - Hero

    private func heroSection(playlist: BrowsePlaylistDetail, topSafeInset: CGFloat) -> some View {
        KimaDetailHero(topInset: topSafeInset) {
            coverArt(playlist: playlist)
        } info: {
            KimaKicker(title: "Deezer playlist")
            KimaDetailHeroTitle(text: playlist.title)
            if let creator = playlist.creator, !creator.isEmpty {
                KimaDetailHeroByline(text: creator)
            }
            KimaDetailHeroMeta(parts: ["\(playlist.trackCount) \(playlist.trackCount == 1 ? "track" : "tracks")"])
        }
    }

    // MARK: - Action row

    /// Import (when the playlist has a source address) and, while a preview plays, stop.
    private func actionRow(playlist: BrowsePlaylistDetail) -> some View {
        HStack(spacing: KimaSpacing.md) {
            if let url = playlist.url, !url.isEmpty {
                Button {
                    previewer.stop()
                    showImport = true
                } label: {
                    Label("import playlist", systemImage: "square.and.arrow.down")
                        .font(KimaType.captionStrong)
                        .foregroundStyle(KimaColor.onBrand)
                        .padding(.horizontal, KimaSpacing.lg)
                        .frame(minHeight: 44)
                        .background(KimaColor.brand, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("browse-playlist-import")
            }
            if previewer.previewingId != nil {
                Button {
                    previewer.stop()
                } label: {
                    Label("stop preview", systemImage: "stop.fill")
                        .font(KimaType.captionStrong)
                        .foregroundStyle(KimaColor.textPrimary)
                        .padding(.horizontal, KimaSpacing.lg)
                        .frame(minHeight: 44)
                        .overlay(Capsule().strokeBorder(KimaColor.hairline, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.top, KimaSpacing.md)
    }

    @ViewBuilder
    private func coverArt(playlist: BrowsePlaylistDetail) -> some View {
        RemoteArtworkImage(urlString: playlist.imageUrl)
    }

    // MARK: - Track list

    private func trackList(playlist: BrowsePlaylistDetail) -> some View {
        KimaPageStack(count: playlist.tracks.count, alignment: .leading) {
            if playlist.tracks.isEmpty {
                Text("no tracks available")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.top, KimaSpacing.xl)
            } else {
                Text("tap a song for a 30-second preview")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.bottom, KimaSpacing.sm)
                ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                    BrowseTrackRow(
                        index: index + 1,
                        track: track,
                        isPreviewing: previewer.previewingId == track.id,
                        // The payload's previewUrl is a signed Deezer CDN link that expires ~27 h after
                        // the server fetched the playlist — resolve fresh through the server's stream
                        // proxy per playback; the payload URL is only the no-ticket fallback.
                        onTap: track.previewUrl.map { _ in
                            {
                                Task {
                                    await previewer.toggle(id: track.id, mainPlayer: player) {
                                        let tok = await env.client.streamTicket()
                                        return PreviewURL.track(
                                            base: env.server, artistName: track.artist,
                                            trackTitle: track.title, token: tok
                                        ) ?? URL(string: track.previewUrl ?? "")
                                    }
                                }
                            }
                        }
                    )
                    if index < playlist.tracks.count - 1 {
                        KimaHairline()
                            .padding(.horizontal, KimaSpacing.lg)
                    }
                }
            }
        }
        .padding(.top, KimaSpacing.md)
    }

    // MARK: - Data

    private func load() async {
        if playlist == nil { isLoading = true }
        errorMessage = nil
        do {
            playlist = try await env.client.getBrowsePlaylist(id: playlistId)
        } catch {
            if Task.isCancelled { isLoading = false; return }
            if playlist == nil { errorMessage = "couldn't load this playlist" }
        }
        isLoading = false
    }
}

// MARK: - BrowseTrackRow

/// One track row. With a Deezer `previewUrl` the row is a button that toggles the 30-second
/// preview (animated waveform in the index column while it plays); without one it is static.
private struct BrowseTrackRow: View {
    let index: Int
    let track: BrowsePlaylistTrack
    /// Whether this row's Deezer preview is currently playing.
    let isPreviewing: Bool
    /// Tap action that toggles the preview. Nil when the track has no previewUrl.
    let onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            Button(action: onTap) { rowContent }
                .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    // MARK: - Row content

    private var rowContent: some View {
        TrackRow(number: "\(index)", artwork: .remote(track.coverUrl), title: track.title, subtitle: track.artist,
                 duration: track.durationFormatted.isEmpty ? nil : track.durationFormatted,
                 nowPlaying: isPreviewing ? .playing : .none)
        .padding(.horizontal, KimaSpacing.lg)
    }
}
