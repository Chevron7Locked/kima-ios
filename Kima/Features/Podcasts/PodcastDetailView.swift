import SwiftUI

// MARK: - PodcastDetailView

/// Podcast detail in two modes, resolved by the VM: subscribed (Kima id) shows episodes,
/// actions and similar; unsubscribed (iTunes id) shows PodcastPreviewView. `PodcastDetailView(id:)`.
struct PodcastDetailView: View {
    let id: String

    @Environment(AppEnvironment.self) var env  // internal: +EpisodeList extension file
    @Environment(PlaybackController.self) var player  // internal: +EpisodeList extension file
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @State var vm: PodcastDetailViewModel  // internal: +EpisodeList extension file
    @State private var palette: CoverArtPalette?
    @State private var heroHeight: CGFloat = 0
    @State private var similarDetailId: String?
    /// A category pill's chart (Apple category id).
    @State private var chartCategoryId: Int?
    @State var episodeFilter: PodcastEpisodeFilter = .all  // internal: +EpisodeList extension file

    init(id: String) {
        self.id = id
        _vm = State(initialValue: PodcastDetailViewModel(id: id))
    }

    var body: some View {
        Group {
            switch vm.mode {
            case .loading:
                loadingView
            case .error(let msg):
                errorView(msg)
            case .subscribed(let podcast):
                subscribedBody(podcast)
            case .preview(let preview):
                PodcastPreviewView(
                    preview: preview,
                    itunesId: id,
                    palette: palette,
                    isSubscribing: vm.isSubscribing,
                    similar: vm.similar,
                    onSubscribe: {
                        guard let feedUrl = preview.feedUrl else { return }
                        if try await vm.subscribe(feedUrl: feedUrl, itunesId: preview.itunesId, client: env.client) != nil {
                            toastCenter.show("following", style: .success)
                        } else {
                            toastCenter.show("couldn't follow. try again.", style: .error)
                        }
                    },
                    onOpenCategory: { chartCategoryId = $0 },
                    onOpenShow: { similarDetailId = $0 }
                )
                .task(id: preview.coverUrl) {
                    palette = await CoverArtColor.palette(coverId: preview.coverUrl, server: env.server)
                }
            }
        }
        .background(KimaScreenGround())
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadIfNeeded(client: env.client) }
        .navigationDestination(item: $similarDetailId) { PodcastDetailView(id: $0) }
        .navigationDestination(item: $chartCategoryId) { PodcastChartDestination(categoryId: $0) }
        .onChange(of: vm.episodeSort) { _, _ in
            Task {
                await vm.sortChanged(client: env.client)
                if case .subscribed(let podcast) = vm.mode {
                    player.updatePodcastQueue(podcastId: podcast.id, episodes: vm.sortedEpisodes())
                }
            }
        }
    }

    // MARK: - Phase views

    private var loadingView: some View {
        KimaLoadingState()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        KimaErrorState(message: message) { Task { await vm.load(client: env.client) } }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Subscribed body

    @ViewBuilder
    private func subscribedBody(_ podcast: Podcast) -> some View {
        let playingEpisodeId: String? = {
            if case .podcastEpisode(_, let ep, _) = player.playbackType { return ep.id }
            return nil
        }()
        let isThisPodcastPlaying: Bool = {
            if case .podcastEpisode(let pid, _, _) = player.playbackType { return pid == podcast.id }
            return false
        }()
        let continueEps = vm.continueListening()
        let sortedEps   = vm.sortedEpisodes()

        KimaTopInsetReader { topInset in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Hero — shared with preview mode via PodcastHeroView
                    PodcastHeroView(
                        coverUrl: podcast.coverUrl,
                        title: podcast.title,
                        author: podcast.author,
                        genres: (podcast.categories ?? []).isEmpty ? podcast.genres : nil,
                        episodeCount: podcast.episodeCount,
                        topSafeInset: topInset
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }

                    PodcastCategoryPills(categories: podcast.categories ?? []) { chartCategoryId = $0 }

                    subscribedActionBar(podcast, isPlaying: isThisPodcastPlaying, episodes: sortedEps)
                        .padding(.horizontal, KimaSpacing.lg)
                        .padding(.top, KimaSpacing.xl)

                    if !continueEps.isEmpty {
                        // Stacked text rows (title + inline
                        // meta + thin progress under the text), not a boxed horizontal carousel.
                        // Cap 4 — the stack must not push the episode list off the first screen.
                        KimaSectionHeader(title: "continue listening")
                        VStack(spacing: 0) {
                            ForEach(continueEps.prefix(4)) { ep in
                                EpisodeRowView(
                                    episode: ep,
                                    isPlaying: ep.id == playingEpisodeId,
                                    onPlay: { playOrToggle(ep, podcast: podcast, queue: sortedEps) },
                                    onMarkComplete: { Task { await vm.markEpisodeComplete(episode: ep, client: env.client) } },
                                    onDeleteProgress: { Task { await vm.deleteEpisodeProgress(episode: ep, client: env.client) } }
                                )
                                .padding(.horizontal, KimaSpacing.lg)
                            }
                        }
                        .padding(.bottom, KimaSpacing.xs)
                    }

                    episodeListSection(podcast: podcast, episodes: sortedEps, playingId: playingEpisodeId)

                    if let desc = podcast.description, !desc.strippingHTML.isEmpty {
                        AboutSection(text: desc.strippingHTML)
                    }

                    if !vm.similar.isEmpty {
                        similarSection()
                    }

                    unsubscribeRow
                }
                .kimaReadableWidth()
                .frame(maxWidth: .infinity)
            }
            .kimaMiniPlayerClearance()
            // Let the hero backdrop reach the true top edge (under the notch); only .top so the
            // bottom mini-player / tab-bar insets stay intact.
            .ignoresSafeArea(.container, edges: .top)
            .kimaHeroGround(heroHeight: heroHeight) {
                PodcastHeroBackdrop(coverUrl: podcast.coverUrl, palette: palette)
            }
            // Pull-to-refresh checks the feed for new episodes and re-seeds the episode list.
            // Failures toast — never silent.
            .refreshable {
                do { try await vm.refresh(client: env.client) }
                catch { toastCenter.show("couldn't refresh podcast", style: .error) }
            }
            .task(id: podcast.coverUrl) {
                palette = await CoverArtColor.palette(coverId: podcast.coverUrl, server: env.server)
            }
        }
    }

    // MARK: - Action bar (subscribed)

    @ViewBuilder
    private func subscribedActionBar(_ podcast: Podcast, isPlaying: Bool, episodes: [Episode]) -> some View {
        HStack(spacing: KimaSpacing.md) {
            // Play Latest / Pause
            KimaHeroPlayButton(isPlaying: isPlaying, label: isPlaying ? "pause" : "play latest episode") {
                if isPlaying {
                    player.togglePlayPause()
                } else if let ep = vm.playLatestEpisode() {
                    player.playPodcastEpisode(ep, podcast: podcast, queue: episodes, client: env.client)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Unsubscribe (destructive — its own group at the foot of the page)

    private var unsubscribeRow: some View {
        KimaDestructiveRow(
            label: "unsubscribe",
            confirmTitle: "unsubscribe?",
            confirmMessage: "this removes all episodes and your listening progress. this cannot be undone.",
            confirmButton: "unsubscribe"
        ) {
            Task {
                do {
                    try await vm.unsubscribe(client: env.client)
                    toastCenter.show("unsubscribed", style: .success)
                    NotificationCenter.default.post(name: .kimaPodcastUnsubscribed, object: vm.activeId)
                    dismiss()
                } catch {
                    toastCenter.show("couldn't unsubscribe", style: .error)
                }
            }
        }
        .padding(.bottom, KimaSpacing.xl)
    }

    // MARK: - Play helper

    /// Start the episode, or — if it is already the current episode — just toggle pause/resume (no reload from the resume point).
    func playOrToggle(_ ep: Episode, podcast: Podcast, queue: [Episode]) {  // internal: +EpisodeList extension file
        if case .podcastEpisode(_, let cur, _) = player.playbackType, cur.id == ep.id {
            player.togglePlayPause()
        } else {
            player.playPodcastEpisode(ep, podcast: podcast, queue: queue, client: env.client)
        }
        // Continuous play must not stop at the end of the loaded pages: page in more as playback nears the tail and
        // push the grown queue into the player (auto-advance walks its own snapshot).
        Task {
            await vm.loadMoreIfNeeded(client: env.client, currentEpisode: ep)
            let refreshed = vm.sortedEpisodes()
            player.updatePodcastQueue(podcastId: podcast.id, episodes: refreshed)
        }
    }

    // MARK: - Similar podcasts section

    private func similarSection() -> some View {
        VStack(spacing: 0) {
            KimaSectionHeader(title: "more like this")
            KimaRail(tileWidth: PodcastCardView.cardWidth) { width in
                ForEach(vm.similar) { podcast in
                    PodcastCardView(discovery: podcast, width: width) { similarDetailId = podcast.id }
                }
            }
        }
    }
}
