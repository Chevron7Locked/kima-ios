import SwiftUI

// The 5th tab: a menu of Discover Weekly, Vibe Map, Radio, Releases, Playlists, Stats,
// Downloads, Import and Settings, plus inline search. Entries push into this view's own
// NavigationStack; podcast and audiobook results use typed `.navigationDestination(item:)`.

/// Typed wrappers so podcast and audiobook item-navigation can't collide on a shared `String?`.
private struct MorePodcastNav: Hashable { let id: String }
private struct MoreAudiobookNav: Hashable { let id: String }

/// What a menu row opens: a pushed screen, or the import sheet.
private enum MoreDestination: Hashable {
    case discover, radio, releases, browsePlaylists, downloads, stats, settings, importPlaylists
}

struct MoreView: View {
    /// Threaded straight from AppShellView.
    let host: String
    let onSignOut: () -> Void
    let onChangeServer: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast

    /// This hub's own NavigationStack path — shared by album/artist/playlist detail and the
    /// inline search results (artist/album taps).
    @State private var path: [LibraryRoute] = []
    @State private var featuredPlaylists: [HomePlaylistPreview] = []

    // Inline search state.
    @State private var searchVM = SearchViewModel()
    @State private var isSearchFocused = false
    @State private var searchPodcast: MorePodcastNav?
    @State private var searchAudiobook: MoreAudiobookNav?

    @State private var destination: MoreDestination?
    /// Stats asked for from outside More (the full player, what's new) while a menu screen is open:
    /// pushed from inside that screen, so it stacks on top and back returns to it.
    @State private var statsOnTop = false
    @State private var librarySync = LibrarySyncModel()
    @State private var isAdmin = false

    /// Whether the search surface (vs the menu) is showing — driven by the field having text.
    private var isSearching: Bool { !searchVM.query.isEmpty }

    /// The pushed screen, if any (everything but the import sheet).
    private var pushed: Binding<MoreDestination?> {
        Binding(get: { destination == .importPlaylists ? nil : destination },
                set: { destination = $0 })
    }

    private var showImport: Binding<Bool> {
        Binding(get: { destination == .importPlaylists },
                set: { if !$0, destination == .importPlaylists { destination = nil } })
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                masthead
                KimaSearchField(prompt: "artists, albums, songs…", text: $searchVM.query, isFocused: $isSearchFocused)
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.vertical, KimaSpacing.md)
                if isSearching {
                    SearchResultsArea(
                        vm: searchVM,
                        onPlayTracks: { tracks, idx in player.play(tracks: tracks, startAt: idx) },
                        onPushRoute: handleSearchRoute
                    )
                } else {
                    menu
                }
            }
            // Root stack pinned to the viewport: its ideal width follows children's ideals,
            // and the inflated value centers it off-screen (search field clipped at the left).
            .kimaViewportWidth()
            .kimaScreenCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .libraryRouteDestinations(path: $path)
            .navigationDestination(item: $searchPodcast) { nav in
                PodcastDetailView(id: nav.id)
            }
            .navigationDestination(item: $searchAudiobook) { nav in
                AudiobookDetailView(id: nav.id)
            }
            .navigationDestination(item: pushed) { screen in
                Group {
                    switch screen {
                    case .discover:        DiscoverView()
                    case .radio:           RadioView()
                    case .releases:        ReleasesView()
                    case .browsePlaylists: BrowsePlaylistsView(playlists: featuredPlaylists, path: $path)
                    case .downloads:       ActiveDownloadsView()
                    case .stats:           StatsView(env: env)
                    case .settings:        SettingsView(host: host, onSignOut: onSignOut, onChangeServer: onChangeServer)
                    case .importPlaylists: EmptyView()
                    }
                }
                // Declared inside the pushed screen, so Stats goes on top of it.
                .navigationDestination(isPresented: $statsOnTop) { StatsView(env: env) }
            }
        }
        .onChange(of: destination) { _, _ in statsOnTop = false }
        // Bell hides on any pushed screen. `path` covers album/artist/playlist; the menu push
        // and the search detail item-navs are folded in so the bell never covers a pushed nav bar.
        .publishesNavDepth(
            tab: .more,
            count: path.count + ((pushed.wrappedValue != nil || searchPodcast != nil || searchAudiobook != nil) ? 1 : 0)
                + (statsOnTop ? 1 : 0),
            to: env.router
        )
        .task {
            featuredPlaylists = (try? await env.client.getFeaturedPlaylists()) ?? []
        }
        .task {
            isAdmin = (try? await env.client.me())?.role == "admin"
        }
        .task {
            await searchVM.loadSoulseekStatus(client: env.client)
        }
        .onChange(of: searchVM.query) { _, _ in
            searchVM.onQueryChange(client: env.client)
        }
        .onChange(of: searchVM.activeFilter) { _, _ in
            searchVM.onFilterChange(client: env.client)
        }
        .onDisappear {
            searchVM.cancelInFlight()
            librarySync.cancel()
        }
        .onChange(of: env.events.lastScan) { _, scan in
            if let scan { librarySync.apply(scan) }
        }
        // Consume a go-to-target from the whats-new gate (routes /stats* here).
        // .task covers "tab created by the jump" (onChange misses first render);
        // onChange covers "tab already installed".
        .task { consumeStatsRequest() }
        .onChange(of: env.router.statsRequest) { _, want in
            if want { consumeStatsRequest() }
        }
        #if DEBUG
        .task {
            switch DebugDeepLink.requested {
            case "settings": destination = .settings
            case "search":   isSearchFocused = true
            case "downloads": destination = .downloads
            case "stats": destination = .stats
            case "playlists", "playlist": path.append(LibraryRoute.playlists)
            case "discover":  destination = .discover
            case "designlab": path.append(LibraryRoute.designlab)
            case "licenses":  path.append(LibraryRoute.licenses)
            case "changelog": path.append(LibraryRoute.changelog)
            default:         break
            }
        }
        #endif
        .sheet(isPresented: showImport) {
            ImportView()
                .appEnvironment(env, toast)
        }
    }

    // MARK: - Search routing

    /// Stats opens on top of whatever menu screen is open, so back returns to it, or on its own when none
    /// is; nothing changes when Stats already shows.
    private func consumeStatsRequest() {
        guard env.router.statsRequest else { return }
        env.router.statsRequest = false
        guard destination != .stats else { return }
        if pushed.wrappedValue != nil { statsOnTop = true } else { destination = .stats }
    }

    /// Route an inline-search tap into this hub's own NavigationStack: artist/album go on the
    /// `LibraryRoute` path (already handled above); podcast/audiobook use typed item-navs.
    private func handleSearchRoute(_ route: SearchRoute) {
        switch route {
        case .artist(let id):    path.append(.artist(id: id))
        case .album(let id):     path.append(.album(id: id))
        case .podcast(let id):   searchPodcast = MorePodcastNav(id: id)
        case .audiobook(let id): searchAudiobook = MoreAudiobookNav(id: id)
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        KimaScreenHeader(title: "more")
    }

    // MARK: - Menu (shown when the search field is empty)

    private var menu: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                MoreSection(title: "explore") {
                    MoreRow(
                        icon: "safari",
                        title: "discover weekly",
                        description: "new albums picked from what you play, every week"
                    ) { destination = .discover }
                    MoreRow(
                        icon: "point.3.connected.trianglepath.dotted",
                        title: "vibe map",
                        description: "browse your library by sound"
                    ) {
                        env.router.showVibeMap = true
                    }
                    MoreRow(
                        icon: "dot.radiowaves.left.and.right",
                        title: "library radio",
                        description: "stations by genre and decade from your library"
                    ) { destination = .radio }
                    MoreRow(
                        icon: "calendar",
                        title: "new releases",
                        description: "new and upcoming albums from your artists"
                    ) { destination = .releases }
                    MoreRow(
                        icon: "rectangle.stack.fill",
                        title: "browse playlists",
                        description: "featured playlists from Deezer",
                        showDivider: false
                    ) { destination = .browsePlaylists }
                }

                MoreSection(title: "your music") {
                    MoreRow(
                        icon: "music.note.list",
                        title: "playlists",
                        description: "your playlists"
                    ) { path.append(.playlists) }
                    MoreRow(
                        icon: "chart.bar.xaxis",
                        title: "stats",
                        description: "how much you listen and what you play most",
                        showDivider: false
                    ) { destination = .stats }
                }

                MoreSection(title: "manage") {
                    MoreRow(
                        icon: "arrow.down.circle",
                        title: "downloads",
                        description: "albums downloading to your server"
                    ) { destination = .downloads }
                    MoreRow(
                        icon: "link.badge.plus",
                        title: "import",
                        description: "import playlists from Spotify, Deezer, YouTube, or SoundCloud",
                        showDivider: isAdmin
                    ) { destination = .importPlaylists }
                    if isAdmin {
                        MoreRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "sync library",
                            description: librarySync.description,
                            showDivider: false
                        ) { librarySync.start(client: env.client) }
                    }
                }

                settingsFooter
            }
            .kimaViewportWidth()
        }
        .kimaMiniPlayerClearance()
    }

    // MARK: - Settings footer

    /// Settings and the problem reporter close the menu as their own group, a section's distance below "manage".
    private var settingsFooter: some View {
        VStack(spacing: 0) {
            MoreRow(
                icon: "gearshape",
                title: "settings",
                description: "account, connection, playback, appearance"
            ) { destination = .settings }
            MoreRow(
                icon: "exclamationmark.bubble",
                title: "report a problem",
                description: "send it to github or save it on the phone",
                showDivider: false
            ) { env.router.showIssueReporter = true }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.top, KimaSpacing.xxl)
    }
}

// MARK: - Preview

#Preview {
    let env = AppEnvironment(server: KimaServer(baseURL: URL(string: "https://kima.example.com")!))
    MoreView(host: "kima.example.com", onSignOut: {}, onChangeServer: {})
        .environment(env)
        .environment(env.player)
        .environment(ToastCenter())
}
