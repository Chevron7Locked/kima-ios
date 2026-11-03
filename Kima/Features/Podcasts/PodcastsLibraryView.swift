import SwiftUI

// MARK: - PodcastRoute

/// Navigation routes within the Podcasts feature.
/// The library owns a NavigationStack keyed on this enum so all sub-navigation
/// stays within the Podcasts tab without touching the global LibraryRoute.
enum PodcastRoute: Hashable {
    case detail(id: String)
    /// An Apple chart: a category's, or the overall chart for nil.
    case chart(categoryId: Int?)
    /// Every top-level category.
    case categories
}

// MARK: - PodcastsLibraryView

/// Podcast library: continue listening and new episodes, your shows, then discovery (for you, top shows, a few
/// category rows, the categories list) and RSS subscribe. Owns its NavigationStack and is the "see all" target
/// from the Home podcasts section.
struct PodcastsLibraryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self)    private var toastCenter
    @Environment(PlaybackController.self) private var player

    @State private var vm           = PodcastsLibraryViewModel()
    @State private var path: [PodcastRoute] = []
    @State private var showAddSheet = false
    @State private var sortOption   = PodcastLibrarySortOption.title
    @State private var pageSize     = 50

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        PodcastEpisodeRails(
                            continueItems: vm.continueRows,
                            newItems: vm.newRows,
                            podcast: vm.podcast(for:),
                            onOpenShow: { path.append(.detail(id: $0)) }
                        )
                        myPodcastsSection
                        PodcastDiscoverySections(vm: vm) { path.append($0) }
                            .id("kimaPodcastDiscovery")
                        Spacer(minLength: KimaSpacing.lg)
                    }
                    .kimaViewportWidth()
                }
                .kimaMiniPlayerClearance()
                .kimaScrollTopGround()
                #if DEBUG
                // Screenshot hook: `-kima-scroll-podcast-discovery` scrolls to the discovery rows.
                .task {
                    guard CommandLine.arguments.contains("-kima-scroll-podcast-discovery") else { return }
                    try? await Task.sleep(for: .seconds(4))
                    proxy.scrollTo("kimaPodcastDiscovery", anchor: .top)
                }
                #endif
            }
            // Nav bar hidden: the editorial header lives in the scroll.
            .toolbar(.hidden, for: .navigationBar)
            // Pull-to-refresh re-runs the full load (category rows included) and, alongside it, asks the server
            // to check every feed for new episodes; the shows list reloads again when that slower check finishes.
            // A part that fails keeps what it had.
            .refreshable {
                Task {
                    do {
                        try await vm.refreshAll(client: env.client)
                        await vm.refreshSubscribed(client: env.client)
                    } catch {
                        toastCenter.show("couldn't check feeds for new episodes", style: .error)
                    }
                }
                await vm.load(client: env.client, force: true)
            }
            .navigationDestination(for: PodcastRoute.self) { route in
                switch route {
                case .detail(let id):
                    PodcastDetailView(id: id)
                case .chart(let categoryId):
                    PodcastChartView(categoryId: categoryId) { discovery in
                        path.append(.detail(id: discovery.id))
                    }
                case .categories:
                    PodcastCategoriesView(categories: vm.categories) { path.append($0) }
                }
            }
            .kimaScreenCanvas()
          }
          .publishesNavDepth(tab: .podcasts, count: path.count, to: env.router)
        .task {
            await vm.load(client: env.client)
            #if DEBUG
            // Screenshot deep-link: push the first subscribed show (see DebugDeepLink).
            if DebugDeepLink.requested == "podcast", path.isEmpty, let first = vm.subscribed.first {
                path.append(.detail(id: first.id))
            }
            // `podcast-chart` opens the comedy chart (Apple id 1303), which has sub-categories.
            if DebugDeepLink.requested == "podcast-chart", path.isEmpty { path.append(.chart(categoryId: 1303)) }
            // `podcast-preview` opens the top chart's first show, which is not followed.
            if DebugDeepLink.requested == "podcast-preview", path.isEmpty,
               let show = vm.topShows.first(where: { top in !vm.subscribed.contains { $0.title == top.title } }) {
                path.append(.detail(id: show.id))
            }
            #endif
        }
        // Back on the page: a show followed from a preview joins "your shows", and "continue" shows where an
        // episode stopped.
        .onChange(of: path.isEmpty) { _, atRoot in
            if atRoot { Task { await vm.refreshSubscribed(client: env.client) } }
        }
        // A rail episode that starts, ends or gives way to another moves between the rails.
        .onChange(of: playingEpisodeId) { _, _ in
            Task { await vm.reloadListening(client: env.client) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kimaPodcastUnsubscribed)) { note in
            if let id = note.object as? String { vm.removeSubscribed(id: id) }
        }
        .sheet(isPresented: $showAddSheet) {
            PodcastAddView { newId in
                path.append(.detail(id: newId))
                // Only your shows and the listening rails change after a follow.
                Task { await vm.refreshSubscribed(client: env.client) }
            }
            .appEnvironment(env, toastCenter)
        }
    }

    private var playingEpisodeId: String? {
        if case .podcastEpisode(_, let episode, _) = player.playbackType { return episode.id }
        return nil
    }

    // MARK: - Editorial header

    private var header: some View {
        KimaScreenHeader(
            title: "podcasts",
            statValue: vm.subscribed.count,
            statLabel: "shows"
        ) {
            Button { showAddSheet = true } label: {
                Label("add podcast", systemImage: "plus")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textSecondary)
                    .kimaHitTarget(growsLayout: false)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - My Podcasts

    @ViewBuilder
    private var myPodcastsSection: some View {
        // Sort sits right-aligned in the section's own header row. (Page size is handled by the
        // "show more" button below — no "N per page" menu on an infinitely-scrolling list.)
        KimaSectionHeader(title: "your shows") {
            if !vm.subscribed.isEmpty {
                Picker("sort", selection: $sortOption) {
                    ForEach(PodcastLibrarySortOption.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .tint(KimaColor.textMuted)
                .font(KimaType.caption)
            }
        }

        if vm.subscribed.isEmpty && !vm.isLoading {
            emptySubscribedState
        } else {
            subscribedList

            if vm.hasMoreSubscribed(pageSize: pageSize) {
                Button("show more") { pageSize += 50 }
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textSecondary)
                    .frame(minHeight: 44)
                    .padding(.horizontal, KimaSpacing.lg)
            }
        }

    }

    // MARK: - Subscribed list

    // Single-column list emitted as a bare `ForEach` into the page's stack. Rows pad themselves to align with the
    // section header.

    private var subscribedList: some View {
        ForEach(vm.displayedSubscribed(sort: sortOption, pageSize: pageSize)) { podcast in
            PodcastLibraryRow(podcast: podcast) {
                path.append(.detail(id: podcast.id))
            }
        }
    }

    // MARK: - Empty subscribed state

    private var emptySubscribedState: some View {
        KimaEmptyState(
            icon: "waveform.badge.plus",
            title: "no shows yet",
            message: "add podcast finds one, or browse below."
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, KimaSpacing.xl)
    }
}
