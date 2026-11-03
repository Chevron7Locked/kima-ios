import SwiftUI

// Composition view — delegates hero, track list, and similar albums to focused subviews.
// File org: AlbumHeroView.swift (hero), AlbumActionBar.swift (action bar),
// AlbumTrackListView.swift (tracks).

// MARK: - Root view

struct AlbumDetailView: View {
    let albumId: String
    @Binding var path: [LibraryRoute]

    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast
    @State private var vm = AlbumDetailViewModel()
    @State private var showMetadataEditor = false
    @State private var trackForEdit: Track? = nil
    @State private var heroHeight: CGFloat = 0

    var body: some View {
        ZStack {
            KimaScreenGround()
            phaseContent
        }
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .task {
            guard CommandLine.arguments.contains("-kima-open-metadata") else { return }
            try? await Task.sleep(for: .seconds(2))
            showMetadataEditor = true
        }
        #endif
        .task { await vm.load(id: albumId, using: env.client) }
        .sheet(isPresented: $showMetadataEditor) {
            if case .loaded(let album) = vm.phase {
                MetadataEditorView(kind: .album(album)) {
                    Task { await vm.load(id: albumId, using: env.client) }
                }
                .appEnvironment(env, toast)
            }
        }
        .sheet(item: $trackForEdit) { track in
            MetadataEditorView(kind: .track(track)) {
                Task { await vm.load(id: albumId, using: env.client) }
            }
            .appEnvironment(env, toast)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch vm.phase {
        case .loading:
            KimaLoadingState { Task { await vm.load(id: albumId, using: env.client) } }
        case .failed(let msg):
            KimaErrorState(message: msg) {
                Task { await vm.load(id: albumId, using: env.client) }
            }
        case .loaded(let album):
            albumContent(album)
        }
    }

    @ViewBuilder
    private func albumContent(_ album: Album) -> some View {
        let isOwned = AlbumDetailViewModel.isOwned(album)
        // The hero's backdrop fills the top under the notch; its content pads down by `topSafeArea`.
        KimaTopInsetReader { topSafeArea in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero: blurred backdrop + dynamic gradient + cover art + info + action bar
                    AlbumHeroView(
                        album: album,
                        isOwned: isOwned,
                        vm: vm,
                        onTapArtist: { id in path.append(.artist(id: id)) },
                        onEdit: isOwned ? { showMetadataEditor = true } : nil,
                        topSafeArea: topSafeArea
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }

                    // Track list: disc-grouped, missing interleaved, preview taps
                    AlbumTrackListView(
                        album: album,
                        isOwned: isOwned,
                        vm: vm,
                        onEditTrack: isOwned ? { track in trackForEdit = track } : nil
                    )
                    .padding(.top, KimaSpacing.xl)

                    // Similar albums carousel with "Owned" badge
                    if let similar = album.similarAlbums, !similar.isEmpty {
                        SimilarAlbumsSection(
                            albums: similar,
                            onTapAlbum: { id in path.append(.album(id: id)) }
                        )
                    }
                }
                .kimaReadableWidth()
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .kimaMiniPlayerClearance()
            // Let the hero backdrop reach the true top edge (the notch). Only .top — the bottom
            // mini-player / tab bar insets stay intact.
            .ignoresSafeArea(.container, edges: .top)
            .kimaHeroGround(heroHeight: heroHeight) {
                AlbumHeroBackdrop(coverId: AlbumHeroView.coverId(for: album))
            }
            // Pull-to-refresh re-fetches via the same library→discovery path as `load`, keeping
            // the current album on screen until the fresh one lands. Failures toast.
            .refreshable {
                do { try await vm.refresh(id: albumId, using: env.client) }
                catch { toast.show("couldn't refresh album", style: .error) }
            }
            .onDisappear { vm.preview.stop() }
            .onChange(of: env.player.isPlaying) { _, playing in
                if playing { vm.preview.stop() }
            }
        }
    }
}

// MARK: - Similar albums with "Owned" badge

private struct SimilarAlbumsSection: View {
    let albums: [SimilarAlbum]
    let onTapAlbum: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: "similar albums")

            KimaRail(tileWidth: 140) { width in
                ForEach(albums) { album in
                    similarCard(album: album, width: width)
                }
            }
        }
    }

    @ViewBuilder
    private func similarCard(album: SimilarAlbum, width: CGFloat) -> some View {
        let subtitle: String? = {
            let parts = [album.artist?.name, album.year.map(String.init)].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }()

        KimaCoverCard(title: album.title, subtitle: subtitle, titleLines: 2, onTap: { onTapAlbum(album.id) }) {
            CoverArtImage(coverId: album.coverArt ?? album.coverUrl, size: 256, cornerRadius: 0)
        } accessory: {
            // Owned badge (web: PlayableCard badge="owned")
            if album.owned == true {
                KimaTag(text: "owned", tone: .strong)
                    .padding(KimaSpacing.sm)
            }
        }
        .frame(width: width)
    }
}
