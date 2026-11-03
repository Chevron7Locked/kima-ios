import SwiftUI

// MARK: - RegularShellView

/// iPad (regular-width) 2-column shell: Sidebar | Content, with a docked now-playing bar. `AppShellView` renders
/// it instead of the `TabView` when `horizontalSizeClass == .regular`. Sections own a `NavigationStack` or are
/// wrapped in one here; Vibe Map renders directly. `env.router.selectedTab` two-way syncs with `selection` for
/// the four shared sections; `.more` (iPhone-only) has no mirror, so stats requests are routed here instead.
struct RegularShellView: View {
    let host: String
    let onSignOut: () -> Void
    let onChangeServer: () -> Void
    let onShowActivity: () -> Void
    /// Opens the full player (presented by `AppShellView`, so player routes know it is up).
    let onExpandPlayer: () -> Void
    /// True while the software keyboard is up: the docked bar hides and nothing docked moves.
    let keyboardUp: Bool

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player

    #if DEBUG
    /// `-kima-open <type>` lands on the matching section (the compact shell reaches these through More).
    @State private var selection: SidebarItem = SidebarItem.debugLanding(for: DebugDeepLink.requested) ?? .home
    #else
    @State private var selection: SidebarItem = .home
    #endif
    /// The playlists section's stack; a sidebar playlist opens on top of the all-playlists page.
    @State private var playlistsPath: [LibraryRoute] = []

    /// The playlist open in the playlists section, marked in the sidebar.
    private var openPlaylistId: String? {
        guard selection == .playlists, case .playlistDetail(let id)? = playlistsPath.last else { return nil }
        return id
    }

    /// The vibe map shows its own now-playing card, so the docked bar steps aside there.
    private var showsDockedBar: Bool {
        player.isActive && !(selection == .vibeMap && player.currentTrack != nil)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            KimaSidebar(
                selection: $selection,
                openPlaylistId: openPlaylistId,
                onShowActivity: onShowActivity,
                onSelectPlaylist: openPlaylist
            )
            .ignoresSafeArea(.keyboard)

            // Content fills the remaining width; the docked bar floats over its bottom edge.
            // Content reserves the bar's height so the last row never hides under it.
            ZStack(alignment: .bottom) {
                contentColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The pin width for `kimaViewportWidth()` feed columns is the content column, not the window: on a
                    // 13" iPad the window is 1032 but the column ~796, so window-pinned feeds clipped under the sidebar.
                    // The column tracks sidebar collapse (236 to 68). The GeometryReader gives the column's exact frame
                    // (the bar is an overlay, and scroll children never widen a GeometryReader's proposal).
                    .overlay {
                        GeometryReader { geo in
                            Color.clear
                                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
                                    if w > 100, env.viewportWidth != w { env.viewportWidth = w }
                                }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        // isActive (not currentTrack): long-form (audiobook/podcast) playback sets isActive without a
                        // currentTrack, so gating on the track would leave long-form sessions with no bar on iPad.
                        if showsDockedBar {
                            Color.clear.frame(height: RegularNowPlayingBar.height)
                        }
                    }

                if showsDockedBar {
                    RegularNowPlayingBar(onExpand: onExpandPlayer)
                        .opacity(keyboardUp ? 0 : 1)      // instant hide while the keyboard is up
                        .allowsHitTesting(!keyboardUp)
                        .ignoresSafeArea(.keyboard)
                }

                OfflineBannerPill()
            }
        }
        .background(KimaColor.base)
        .onChange(of: env.router.selectedTab) { _, tab in syncSelection(fromTab: tab) }
        .onChange(of: selection) { _, item in syncTab(fromSelection: item) }
        // Stats asked for from the full player or a what's-new window opens the stats section.
        .task { consumeStatsRequest() }
        .onChange(of: env.router.statsRequest) { _, want in
            if want { consumeStatsRequest() }
        }
    }

    // MARK: - Content column

    @ViewBuilder
    private var contentColumn: some View {
        @Bindable var router = env.router
        switch selection {
        case .home:
            HomeView(selectedTab: $router.selectedTab)
        case .library:
            LibraryView()
        case .playlists:
            NavigationStack(path: $playlistsPath) {
                PlaylistsListView(path: $playlistsPath)
                    .libraryRouteDestinations(path: $playlistsPath)
            }
        case .discover:
            NavigationStack { DiscoverView() }
        case .radio:
            NavigationStack { RadioView() }
        case .vibeMap:
            VibeMapView(vm: env.vibeMapViewModel, onClose: { selection = .home })
        case .audiobooks:
            AudiobooksLibraryView()
        case .podcasts:
            PodcastsLibraryView()
        case .stats:
            NavigationStack { StatsView(env: env) }
        case .search:
            SearchView()
        case .settings:
            NavigationStack { SettingsView(host: host, onSignOut: onSignOut, onChangeServer: onChangeServer) }
        }
    }

    // MARK: - Navigation sync

    private func syncSelection(fromTab tab: AppTab) {
        switch tab {
        case .home:       selection = .home
        case .library:    selection = .library
        case .audiobooks: selection = .audiobooks
        case .podcasts:   selection = .podcasts
        case .more:       break // iPhone-only hub; on iPad it stands for "an iPad-only section"
        }
    }

    private func syncTab(fromSelection item: SidebarItem) {
        switch item {
        case .home:       env.router.selectedTab = .home
        case .library:    env.router.selectedTab = .library
        case .audiobooks: env.router.selectedTab = .audiobooks
        case .podcasts:   env.router.selectedTab = .podcasts
        case .playlists, .discover, .radio, .vibeMap, .stats, .search, .settings:
            // iPad-only sections park the tab on `.more`, so a later request for one of the four shared
            // tabs (open an artist from stats or the player) always changes the value and is seen.
            env.router.selectedTab = .more
        }
    }

    /// The compact layout opens stats inside More; here it is its own section.
    private func consumeStatsRequest() {
        guard env.router.statsRequest else { return }
        env.router.statsRequest = false
        selection = .stats
    }

    // MARK: - Playlist (sidebar playlist list)

    /// Opens the playlist on top of the all-playlists page, so back leads to every playlist.
    private func openPlaylist(_ id: String) {
        playlistsPath = [.playlistDetail(id: id)]
        selection = .playlists
    }
}

// MARK: - Preview

#Preview {
    let env = AppEnvironment(server: KimaServer(baseURL: URL(string: "https://kima.example.com")!))
    RegularShellView(host: "kima.example.com", onSignOut: {}, onChangeServer: {}, onShowActivity: {},
                     onExpandPlayer: {}, keyboardUp: false)
        .environment(env)
        .environment(env.player)
}
