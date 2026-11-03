import SwiftUI

// MARK: - SearchView
// Standalone Search screen, used as the content column of the iPad regular-width shell (RegularShellView).
// On iPhone, search lives inline on the More hub; this wraps the same `KimaSearchField` + `SearchResultsArea`
// in its own NavigationStack, with an idle prompt as the empty state.
struct SearchView: View {
    @Environment(AppEnvironment.self)    private var env
    @Environment(PlaybackController.self) private var player

    @State private var vm   = SearchViewModel()
    @State private var path: [SearchRoute] = []
    @State private var isSearchFieldFocused = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                KimaScreenHeader(title: "search")
                KimaSearchField(prompt: "artists, albums, songs…", text: $vm.query, isFocused: $isSearchFieldFocused)
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.vertical, KimaSpacing.md)
                if vm.hasSearched || !vm.query.isEmpty {
                    SearchResultsArea(
                        vm: vm,
                        onPlayTracks: { tracks, idx in player.play(tracks: tracks, startAt: idx) },
                        onPushRoute: { path.append($0) }
                    )
                } else {
                    SearchIdlePrompt(
                        onSelect: { filter in
                            vm.activeFilter = filter
                            isSearchFieldFocused = true
                        },
                        soulseekEnabled: vm.soulseekEnabled
                    )
                }
            }
            .kimaReadableWidth()
            .frame(maxWidth: .infinity)
            .kimaScreenCanvas()
            // The masthead is the page title, as on the other sections.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SearchRoute.self) { route in
                destinationView(for: route)
            }
        }
        .task {
            await vm.loadSoulseekStatus(client: env.client)
        }
        .onChange(of: vm.query) { _, _ in
            vm.onQueryChange(client: env.client)
        }
        .onChange(of: vm.activeFilter) { _, _ in
            vm.onFilterChange(client: env.client)
        }
        .onDisappear {
            vm.cancelInFlight()
        }
    }

    // MARK: - Navigation destinations

    @ViewBuilder
    private func destinationView(for route: SearchRoute) -> some View {
        switch route {
        case .album(let id):
            AlbumDetailView(albumId: id, path: libPath)
        case .artist(let id):
            ArtistDetailView(artistId: id, path: libPath)
        case .podcast(let id):
            PodcastDetailView(id: id)
        case .audiobook(let id):
            AudiobookDetailView(id: id)
        }
    }

    /// Maps `SearchRoute` ↔ `LibraryRoute` so `ArtistDetailView` / `AlbumDetailView` can push
    /// sub-routes (album taps inside artist detail, etc.) into this stack.
    private var libPath: Binding<[LibraryRoute]> {
        Binding(
            get: {
                path.compactMap { route -> LibraryRoute? in
                    switch route {
                    case .artist(let id): return .artist(id: id)
                    case .album(let id):  return .album(id: id)
                    case .podcast, .audiobook: return nil
                    }
                }
            },
            set: { newLibPath in
                let nonLib = path.filter { route in
                    switch route {
                    case .artist, .album:      return false
                    case .podcast, .audiobook: return true
                    }
                }
                path = nonLib + newLibPath.compactMap { libRoute -> SearchRoute? in
                    switch libRoute {
                    case .album(let id):  return .album(id: id)
                    case .artist(let id): return .artist(id: id)
                    default:              return nil
                    }
                }
            }
        )
    }
}
