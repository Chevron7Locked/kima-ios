import SwiftUI

// MARK: - HomeView

/// Home tab. Section order is the body of `mainFeed`. Full-screen spinner only on the first load.
struct HomeView: View {
    /// Binding to the shell's selected tab so "See All" taps in the podcast/audiobook
    /// rails can switch directly to the Podcasts or Audiobooks tab.
    @Binding var selectedTab: AppTab

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast
    @State private var vm = HomeViewModel()
    @State private var path: [LibraryRoute] = []
    @State private var showRadio = false
    /// Non-nil triggers a navigationDestination push to AudiobookDetailView.
    @State private var audiobookDetailId: String? = nil
    /// Non-nil triggers a navigationDestination push to PodcastDetailView.
    @State private var podcastDetailId: String? = nil
    /// Pushes DiscoverView from the Discover Weekly banner card.
    @State private var showDiscover = false
    @State private var showVibeMap  = false
    #if DEBUG
    @State private var showMixerDebug = false   // -kima-open-mixer screenshot hook
    #endif
    /// Pushes BrowsePlaylistsView when the Featured Playlists "See All" is tapped.
    @State private var showBrowsePlaylists = false
    /// Pushes ReleasesView from the Releases Radar banner card.
    @State private var showReleasesRadar  = false

    /// A page is open through `.navigationDestination(isPresented:)` or `(item:)`, which `path` doesn't hold. (Vibe Map
    /// is a fullScreenCover that covers the bell anyway, so it's left out.)
    private var isPushedOutsidePath: Bool {
        showRadio || showBrowsePlaylists || showDiscover || showReleasesRadar
            || audiobookDetailId != nil || podcastDetailId != nil
    }
    /// Any page is open over the Home feed.
    private var isCovered: Bool { !path.isEmpty || isPushedOutsidePath }

        var body: some View {
            NavigationStack(path: $path) {
                // .frame(maxWidth: .infinity): makes the ZStack's IDEAL width flexible. A NavigationStack
                // proposes .unspecified, and a ZStack with no width frame takes its widest child's IDEAL
                // (the feed: horizontal rails sum ~1371pt), centering the whole ZStack off-screen —
                // which is how the floating pill landed clipped at the left edge.
                ZStack(alignment: .top) {
                    Group {
                        if vm.isLoading {
                            KimaLoadingState { Task { await vm.loadAll(using: env.client) } }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if vm.isServerUnreachable {
                            KimaErrorState(message: "can't reach your server. check that it's running and your connection is working.") {
                                Task { await vm.loadAll(using: env.client) }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            mainFeed
                        }
                    }
                    // Floating glass chrome, pinned top-leading. A ZStack layer (not an overlay):
                    // overlays are proposed the primary view's IDEAL size, which is wider than the
                    // screen here — the pill centered in that wide space clipped off the left edge.
                    HomeGlassHeader(covered: isCovered)
                        // Fixed viewport width on purpose: the tab container centers fixed-ideal
                        // children (880-wide at x=-220); a 440-wide header centers to x=0 — the
                        // same positioning the feed column rides. Flexible fill here would fill
                        // the 880 and park the pill off-screen.
                        .kimaViewportWidth()
                }
                // FLEXIBLE fill, never a fixed width: the tab container centers a fixed-ideal
                // root (measured x=-220 under sidebarAdaptable's split columns). maxWidth:.infinity
                // fills the container wherever TabView placed it — the idiom the Library tab
                // proves correct on screen.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar(.hidden, for: .navigationBar)
                .kimaScreenCanvas()
            // Floating glass chrome — the feed scrolls UNDER it. Part of the NavigationStack's
            // root content, so it naturally disappears the moment any destination below is pushed
            // (mirrors how the shell's bell/report cluster hides on a pushed detail).
            .libraryRouteDestinations(path: $path)
            .navigationDestination(isPresented: $showRadio) {
                RadioView()
            }
            .navigationDestination(isPresented: $showBrowsePlaylists) {
                BrowsePlaylistsView(playlists: vm.featuredPlaylists, path: $path)
            }
            // Long-form detail destinations: item-binding push, back resets to nil.
            .navigationDestination(item: $audiobookDetailId) { id in
                AudiobookDetailView(id: id)
            }
            .navigationDestination(item: $podcastDetailId) { id in
                PodcastDetailView(id: id)
            }
            .navigationDestination(isPresented: $showDiscover) {
                DiscoverView()
            }
            .navigationDestination(isPresented: $showReleasesRadar) {
                ReleasesView()
            }
        }
        // Bell hides on any pushed screen.
        .publishesNavDepth(
            tab: .home,
            count: path.count + (isPushedOutsidePath ? 1 : 0),
            to: env.router
        )
        .fullScreenCover(isPresented: $showVibeMap) {
            VibeMapView(vm: env.vibeMapViewModel, onClose: { showVibeMap = false })
                .appEnvironment(env, toast)
        }
        .task {
            await vm.loadAll(using: env.client, isRefresh: vm.hasLoadedOnce && !vm.isServerUnreachable)
        }
        // A finished scan or enrichment step: refresh the rails in place (recently added etc.).
        .onChange(of: env.events.libraryTick) { _, _ in
            guard vm.hasLoadedOnce else { return }
            Task { await vm.loadAll(using: env.client, isRefresh: true) }
        }
        // The what's-new panel cleared the saved mood mix (rebuild/remove) — drop its card
        // from the rail. Posted by MoodMixChoiceView (WhatsNewComponents.swift).
        .onReceive(NotificationCenter.default.publisher(for: .kimaMoodMixCleared)) { _ in
            Task { await vm.reloadMixes(using: env.client) }
        }
        #if DEBUG
        .modifier(HomeDebugHooks(
            showMixerDebug: $showMixerDebug, showVibeMap: $showVibeMap,
            showRadio: $showRadio, showReleasesRadar: $showReleasesRadar, path: $path, vm: vm))
        #endif
    }

    // MARK: - Main feed

    private var mainFeed: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Hero — always shown, no data dependency
                HomeHeroView(
                    artistTotal: vm.libraryArtistTotal,
                    albumTotal: vm.libraryAlbumTotal
                )
                .kimaEntrance(0)

                // 1. Library Radio — always shown
                LibraryRadioSection(onSeeAll: { showRadio = true })
                    .id("kimaHomeRadio")
                    .kimaEntrance(1)

                // 1b. Vibe Map — THE hero of the Home feed; always shown.
                // A standalone hero card, not a rail: no section header, no numbered rows.
                VibeMapHero { showVibeMap = true }
                    .kimaEntrance(2)

                // 2. Continue Listening — conditional on non-empty
                if !vm.recentlyListened.isEmpty {
                    ContinueListeningSection(
                        items: vm.recentlyListened,
                        onSeeAll: { selectedTab = .library },
                        onItemTap: { item in
                            switch item.type?.lowercased() {
                            case "artist":    path.append(.artist(id: item.id))
                            case "album":     path.append(.album(id: item.id))
                            case "podcast":   podcastDetailId = item.id
                            case "audiobook": audiobookDetailId = item.id
                            default: break
                            }
                        },
                        onItemPlay: { item in
                            Task { await vm.playRecent(item, using: env.client, player: player, toast: toast) }
                        },
                        playingIds: vm.startingIds
                    )
                }

                // 3. Recently Added — conditional on non-empty
                if !vm.recentlyAdded.isEmpty {
                    HomeArtistRailSection(
                        title: "recently added",
                        onSeeAll: { selectedTab = .library },
                        artists: vm.recentlyAdded,
                        onArtistTap: { id in path.append(.artist(id: id)) }
                    )
                }

                // 4. Made For You — conditional on non-empty
                if !vm.mixes.isEmpty {
                    MadeForYouSection(
                        mixes: vm.mixes,
                        vm: vm,
                        onRefresh: { await vm.refreshMixes(using: env.client, toast: toast) },
                        onMixesReload: { await vm.reloadMixes(using: env.client) },
                        onPlayMix: { mix in
                            await vm.playMix(mix, using: env.client, player: player, toast: toast)
                        }
                    )
                    .id("kimaHomeMixes")
                }

                // 4b/4c. Discover Weekly + Releases Radar entry points — compact two-up
                // discovery row, always shown.
                DiscoveryRow(
                    onDiscoverTap: { showDiscover = true },
                    onReleasesTap: { showReleasesRadar = true }
                )
                .id("kimaHomeDiscoveryRow")

                // 5. Recommended — conditional on non-empty.
                if !vm.recommended.isEmpty {
                    HomeArtistRailSection(
                        title: "recommended",
                        badge: "Last.fm",
                        artists: vm.recommended,
                        onArtistTap: { id in path.append(.artist(id: id)) }
                    )
                }

                // 6. Popular Artists — conditional on non-empty
                // Library-matched artists (id != nil) navigate to ArtistDetailView.
                // Last.FM-only entries (id == nil) are non-interactive.
                if !vm.popularArtists.isEmpty {
                    PopularArtistsSection(
                        artists: vm.popularArtists,
                        onArtistTap: { id in path.append(.artist(id: id)) }
                    )
                }

                // 7. Featured Playlists — always rendered; skeleton when browse loading.
                // See-All → BrowsePlaylistsView (Deezer playlist grid).
                // Card tap → BrowsePlaylistDetailView (Deezer playlist detail).
                FeaturedPlaylistsSection(
                    playlists: vm.featuredPlaylists,
                    isBrowseLoading: vm.isBrowseLoading,
                    onSeeAll: { showBrowsePlaylists = true },
                    onPlaylistTap: { id in path.append(.browsePlaylistDetail(id: id)) }
                )

                // 8. Popular Podcasts — self-hidden when list is empty
                PodcastsHomeSection(
                    onSeeAll: { selectedTab = .podcasts },
                    onPodcastTap: { podcast in podcastDetailId = podcast.id }
                )

                // 9. Audiobooks — self-hidden when list is empty
                AudiobooksHomeSection(
                    onSeeAll: { selectedTab = .audiobooks },
                    onSelectBook: { id in audiobookDetailId = id }
                )

                Spacer(minLength: KimaSpacing.lg)
            }
            .kimaViewportWidth()
        }
        .kimaScrollTopGround()
        .kimaMiniPlayerClearance()
        .refreshable { await vm.loadAll(using: env.client, isRefresh: true) }
        #if DEBUG
        // Screenshot hooks: `-kima-scroll-discovery` / `-kima-scroll-mixes` / `-kima-scroll-radio` scroll the feed to that section so
        // mid-feed sections can be captured without a (currently unreliable) simulator swipe.
        .task {
            let args = CommandLine.arguments
            let target = args.contains("-kima-scroll-mixes") ? "kimaHomeMixes"
                : args.contains("-kima-scroll-discovery") ? "kimaHomeDiscoveryRow"
                : args.contains("-kima-scroll-radio") ? "kimaHomeRadio" : nil
            guard let target else { return }
            try? await Task.sleep(for: .milliseconds(2500))
            // Radio sits just under the top chrome so its section header shows.
            withAnimation { proxy.scrollTo(target, anchor: target == "kimaHomeRadio" ? UnitPoint(x: 0.5, y: 0.25) : .top) }
        }
        #endif
        }
    }
}
