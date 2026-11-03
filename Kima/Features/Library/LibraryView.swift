import SwiftUI

/// Collection screen (parity: /collection): masthead, tab picker, toolbar, then the artists,
/// albums or tracks list with pagination.
struct LibraryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast
    @State private var vm = CollectionViewModel()
    @State private var summary = LibraryShelfSummary()
    @State private var path: [LibraryRoute] = []
    private let topID = "collectionTop"

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Scroll anchor
                            Color.clear.frame(height: 0).id(topID)

                            LibraryMasthead(
                                heardLine: summary.heardLine,
                                // A space holds the line's height until the first page's count arrives.
                                fallback: vm.activeTotal > 0 ? "\(vm.activeTotal.formatted()) \(vm.activeTab.label)" : " ",
                                moods: env.vibeMapViewModel.libraryMoods.shares
                            )

                            // Tab picker — Artists / Albums / Tracks. The toolbar's own vertical
                            // sm padding spaces the control group (picker, toolbar) at 8pt.
                            tabPicker
                                .padding(.horizontal, KimaSpacing.lg)

                            // Toolbar — search + filter + shuffle in one row
                            CollectionToolbarView(
                                activeTab: vm.activeTab,
                                searchText: searchBinding,
                                filter: $vm.filter,
                                sortBy: $vm.sortBy,
                                itemsPerPage: $vm.itemsPerPage,
                                isShuffling: vm.isShuffling,
                                onShuffle: {
                                    Task { await vm.shuffleLibrary(using: env.client, player: player) }
                                },
                                onRefinementChanged: {
                                    vm.applyRefinement(using: env.client)
                                }
                            )
                            // Content
                            contentView
                                .padding(.horizontal, KimaSpacing.lg)
                                .padding(.top, KimaSpacing.sm)
                                .padding(.bottom, KimaSpacing.md)
                                .clipped()

                            // Pagination (only when > 1 page)
                            if vm.totalPages > 1 {
                                PaginationView(
                                    currentPage: vm.currentPage,
                                    totalPages: vm.totalPages,
                                    isLoading: isActiveTabLoading,
                                    onPage: { page in
                                        vm.goToPage(page, using: env.client)
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            proxy.scrollTo(topID, anchor: .top)
                                        }
                                    }
                                )
                                .padding(.bottom, KimaSpacing.lg)
                            }
                        }
                    }
                    .kimaViewportWidth()
                    .kimaMiniPlayerClearance()
                    .kimaScrollTopGround()
                    .scrollBounceBehavior(.basedOnSize)  // no bounce when content fits viewport
                    // Swiping the results dismisses the keyboard — one of the ways out of search.
                    .scrollDismissesKeyboard(.immediately)
                    // Pull-to-refresh re-runs the active tab's load (same cancellable path the
                    // initial `.task` uses). A re-fetch of loaded data keeps current content on
                    // screen and swaps when the page arrives (see CollectionViewModel.loadArtists),
                    // and phase is replaced wholesale — no duplicate rows are possible.
                    .refreshable {
                        async let page: Void = vm.loadActiveTab(using: env.client)
                        await summary.load(using: env.client, force: true)
                        await page
                    }
                }
            }
            .kimaScreenCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .libraryRouteDestinations(path: $path)
        }
        .publishesNavDepth(tab: .library, count: path.count, to: env.router)
        .task { vm.kickLoad(using: env.client) }
        .task { await summary.load(using: env.client) }
        // A finished scan or enrichment step: refetch the shown page in place.
        .onChange(of: env.events.libraryTick) { _, _ in vm.refetchActiveTab(using: env.client) }
        #if DEBUG
        // Screenshot hooks: -kima-library-tab <artists|albums|tracks>, then -kima-library-search <text>.
        .task(id: "kima-library-hooks") {
            if let raw = DebugDeepLink.launchArgValue("-kima-library-tab"), let tab = CollectionTab(rawValue: raw) {
                vm.selectTab(tab, using: env.client)
            }
            if let q = DebugDeepLink.launchArgValue("-kima-library-search") {
                try? await Task.sleep(for: .seconds(2))
                vm.setSearchText(q, using: env.client)
            }
        }
        .task(id: "kima-open-deeplink") {
            guard let want = DebugDeepLink.requested, want == "artist" || want == "album" else { return }
            if want == "album", vm.activeTab != .albums {
                vm.activeTab = .albums
                await vm.loadActiveTab(using: env.client)
            }
            for _ in 0..<50 {
                if want == "artist", let id = vm.sortedArtists.first?.id {
                    path.append(LibraryRoute.artist(id: id)); return
                }
                if want == "album", case .loaded(let list) = vm.albumsPhase, let id = list.first?.id {
                    path.append(LibraryRoute.album(id: id)); return
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        #endif
        // Deep-link: consume a pending route set by NavigationRouter.open(_:). onChange covers a route
        // arriving while visible, onAppear one set before. Clear first, push only if not already on top.
        .onChange(of: env.router.pendingLibraryRoute) { _, _ in consumePendingDeepLink() }
        .onAppear { consumePendingDeepLink() }
    }

    // MARK: - Search bar

    /// Consume a pending deep-link route: clear it first, push unless it is already on top.
    private func consumePendingDeepLink() {
        guard let route = env.router.pendingLibraryRoute else { return }
        env.router.pendingLibraryRoute = nil
        if path.last != route { path.append(route) }
    }


    private var searchBinding: Binding<String> {
        Binding(
            get: { vm.searchText },
            set: { vm.setSearchText($0, using: env.client) }
        )
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        KimaSegmented(
            options: CollectionTab.allCases.map { ($0, $0.label) },
            selection: Binding(
                get: { vm.activeTab },
                set: { vm.selectTab($0, using: env.client) }
            )
        )
    }

    // MARK: - Content routing

    @ViewBuilder
    private var contentView: some View {
        switch vm.activeTab {
        case .artists:
            ArtistsGridView(
                phase: vm.artistsPhase,
                sortedArtists: vm.sortedArtists,
                searchText: vm.searchText,
                playingIds: vm.startingIds,
                onTapArtist: { path.append(.artist(id: $0)) },
                // The grid rows carry no track lists, so this fetches the artist's full record first
                // (seconds). The card's badge spins through that wait and ignores repeat taps.
                onPlayArtist: { id in
                    Task { await vm.playArtist(id: id, using: env.client, player: player, toast: toast) }
                },
                onRetry: { vm.refetchActiveTab(using: env.client) }
            )

        case .albums:
            AlbumsGridView(
                phase: vm.albumsPhase,
                searchText: vm.searchText,
                busyIds: vm.startingIds,
                onTapAlbum: { path.append(.album(id: $0)) },
                onPlayAlbum: { id in
                    Task { await vm.playAlbum(id: id, using: env.client, player: player, toast: toast) }
                },
                onRetry: { vm.refetchActiveTab(using: env.client) }
            )

        case .tracks:
            TracksListView(
                phase: vm.tracksPhase,
                searchText: vm.searchText,
                currentTrackId: player.currentTrack?.id,
                onPlayTrack: { idx, tracks in
                    player.play(tracks: tracks, startAt: idx)
                },
                onRetry: { vm.refetchActiveTab(using: env.client) }
            )
        }
    }

    // MARK: - Helpers

    private var isActiveTabLoading: Bool {
        switch vm.activeTab {
        case .artists:
            if case .loading = vm.artistsPhase { return true }
        case .albums:
            if case .loading = vm.albumsPhase { return true }
        case .tracks:
            if case .loading = vm.tracksPhase { return true }
        }
        return false
    }
}

