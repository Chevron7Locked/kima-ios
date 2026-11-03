import SwiftUI

/// Artist detail screen: `ArtistHeroView` above the scrollable sections (`ArtistSectionsView`).
/// The cover palette loads once the artist resolves and flows to both.
struct ArtistDetailView: View {
    let artistId: String
    @Binding var path: [LibraryRoute]

    @Environment(AppEnvironment.self) private var env
    @State private var vm = ArtistDetailViewModel()
    @State private var didAppearOnce = false

    var body: some View {
        ZStack {
            KimaScreenGround()
            phaseContent
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(id: artistId, using: env.client) }
        // The view lives on in the navigation stack, so `.task` runs once per push. Albums
        // imported after the first visit would stay invisible until back-out-and-re-enter;
        // re-fetch on re-entry (the web refetches on every mount). `load` keeps the shown
        // content while the fetch runs, so this swap is silent.
        .onAppear {
            if didAppearOnce {
                Task { await vm.load(id: artistId, using: env.client) }
            }
            didAppearOnce = true
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch vm.phase {
        case .loading:
            KimaLoadingState { Task { await vm.load(id: artistId, using: env.client) } }
        case .failed:
            // Friendly, generic copy — the exact cause is captured durably in
            // artist-load-errors.json (see ArtistLoadDiagnostics), not shown to the user.
            KimaErrorState(message: "couldn't load this artist.") {
                Task { await vm.load(id: artistId, using: env.client) }
            }
        case .loaded(let artist):
            ArtistDetailContent(artist: artist, vm: vm, path: $path)
                .task(id: artist.id) {
                    await vm.loadPalette(artist: artist, server: env.server)
                }
        }
    }
}

// MARK: - Content

/// Lays out the hero (full-bleed) above the scrollable sections.
/// Receives the resolved `Artist` directly so the hero and sections share the same value.
private struct ArtistDetailContent: View {
    let artist: Artist
    let vm: ArtistDetailViewModel
    @Binding var path: [LibraryRoute]

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast

    @State private var showMetadataEditor = false
    @State private var heroHeight: CGFloat = 0

    private var source: ArtistSource { ArtistDetailViewModel.source(for: artist) }
    private var albums: [Album] { artist.albums ?? [] }

    var body: some View {
        KimaTopInsetReader { topInset in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero: rounded art + metadata + action bar; the backdrop is pinned behind the page below.
                ArtistHeroView(
                    artist: artist,
                    source: source,
                    albums: albums,
                    isLoadingAction: vm.isLoadingAction,
                    onPlayAll: {
                        Task { await vm.playAll(artist: artist, client: env.client, player: player, toast: toast) }
                    },
                    onShuffle: {
                        Task { await vm.shuffleAll(artist: artist, client: env.client, player: player, toast: toast) }
                    },
                    onRadio: source == .library ? {
                        Task { await vm.startRadio(artist: artist, client: env.client, player: player, toast: toast) }
                    } : nil,
                    onDownloadAll: {
                        Task { await vm.downloadArtist(artist, client: env.client, toast: toast) }
                    },
                    onEdit: source == .library ? { showMetadataEditor = true } : nil,
                    topSafeInset: topInset
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }

                // Scrollable body: bio → popular → discography → available → similar
                ArtistSectionsView(
                    artist: artist,
                    vm: vm,
                    albums: albums,
                    onTapAlbum: { path.append(.album(id: $0)) },
                    onTapArtist: { id in path.append(.artist(id: id)) },
                    server: env.server
                )
            }
            .kimaReadableWidth()
            .frame(maxWidth: .infinity)
        }
        .kimaMiniPlayerClearance()
        .ignoresSafeArea(.container, edges: .top)
        .kimaHeroGround(heroHeight: heroHeight) {
            ArtistHeroBackdrop(coverId: ArtistHeroView.coverId(for: artist), palette: vm.palette)
        }
        }
        .onDisappear { vm.preview.stop() }
        .onChange(of: player.isPlaying) { _, playing in
            if playing { vm.preview.stop() }
        }
        .sheet(isPresented: $showMetadataEditor) {
            MetadataEditorView(kind: .artist(artist)) {
                Task { await vm.load(id: artist.id, name: artist.effectiveName, using: env.client) }
            }
            .appEnvironment(env, toast)
        }
    }
}
