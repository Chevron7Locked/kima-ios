import Foundation
import Observation

// MARK: - PodcastDetailViewModel

@MainActor
@Observable
final class PodcastDetailViewModel {
    let id: String

    private(set) var mode: PodcastDetailMode = .loading
    /// "more like this": shows on the charts of this show's categories.
    private(set) var similar: [DiscoveryPodcast] = []
    private(set) var isSubscribing = false

    // MARK: - Paging state (GET /podcasts/:id returns the first page, 50 newest-first)

    /// Accumulated episodes, newest-first (server page order). Grows via loadNextPage().
    private(set) var allEpisodes: [Episode] = []
    /// The podcast id paging/progress calls use. == id for subscribed detail; switches to the
    /// resolved Kima id after subscribe-from-preview (iTunes id → Kima id redirect).
    private(set) var activeId: String
    /// Server-side total (detail.episodeTotal / page.total). Nil until first response.
    private(set) var episodeTotal: Int?
    /// True when all server episodes are accumulated (episodes >= total).
    private(set) var reachedEnd = false
    private var isLoadingPage = false

    /// Oldest-first accumulator, paged with the server's `order=oldest` so "oldest" starts at the
    /// first episode. Used while that sort is shown and the newest-first list is incomplete.
    private(set) var oldestEpisodes: [Episode] = []
    private var oldestReachedEnd = false
    private(set) var isLoadingOldestPage = false

    /// The episode list's sort, remembered per podcast.
    var episodeSort: PodcastEpisodeSort {
        didSet { UserDefaults.standard.set(episodeSort.rawValue, forKey: Self.sortKey(id)) }
    }

    init(id: String) {
        self.id = id
        self.activeId = id
        let raw = UserDefaults.standard.string(forKey: Self.sortKey(id))
        self.episodeSort = raw.flatMap(PodcastEpisodeSort.init(rawValue:)) ?? .newest
    }

    private static func sortKey(_ id: String) -> String { "kima.podcast.sort.\(id)" }

    // MARK: - Load (dual-mode)

    /// Try subscribed first (GET /podcasts/:id). Falls back to preview on any error.
    /// If the preview reports `isSubscribed`, transparently redirects to the subscribed view.
    func load(client: KimaAPIClient) async {
        mode = .loading
        do {
            let podcast = try await client.getPodcast(id: id)
            seed(from: podcast)
            mode = .subscribed(podcast)
            fetchSimilar(podcastId: id, client: client)
            await sortChanged(client: client)
        } catch {
            await loadAsPreview(itunesId: id, client: client)
        }
    }

    /// First load, or a retry after an error. A re-appearing screen keeps what it shows.
    func loadIfNeeded(client: KimaAPIClient) async {
        switch mode {
        case .loading, .error: await load(client: client)
        case .subscribed, .preview: return
        }
    }

    /// Seeds the accumulator from the detail response's first page (newest-first). loadNextPage()
    /// appends later pages at the tail.
    private func seed(from podcast: Podcast) {
        allEpisodes = podcast.episodes
        episodeTotal = podcast.episodeTotal ?? podcast.episodes.count
        reachedEnd = allEpisodes.count >= (podcast.episodeTotal ?? podcast.episodes.count)
        oldestEpisodes = []
        oldestReachedEnd = false
    }

    // MARK: - Paging

    /// Loads the next page in the shown sort (offset = accumulated count) and appends. Safe to call
    /// from .onAppear of the last visible row; serialized by isLoadingPage, stops at reachedEnd.
    func loadNextPage(client: KimaAPIClient) async {
        if usesOldestPages { return await loadNextOldestPage(client: client) }
        guard !reachedEnd, !isLoadingPage, mode.isSubscribedMode else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        do {
            let page = try await client.getPodcastEpisodesPage(id: activeId, limit: 200, offset: allEpisodes.count)
            // Append-only, dedup by id: an episode published between page fetches shifts offsets
            // and yields a duplicate (server doc: "the reader sees a duplicate"); drop re-sends.
            let seen = Set(allEpisodes.map(\.id))
            let fresh = page.episodes.filter { !seen.contains($0.id) }
            allEpisodes.append(contentsOf: fresh)
            episodeTotal = page.total
            reachedEnd = allEpisodes.count >= page.total || page.episodes.isEmpty
        } catch {
            // Non-fatal: the list keeps what it has; the Load More button retries.
        }
    }

    /// Called by the view when an episode nears the end of the list is about to appear.
    func loadMoreIfNeeded(client: KimaAPIClient, currentEpisode: Episode) async {
        guard canLoadMore else { return }
        // Trigger on the 45th of 50 (and equivalent fractions) so a continuous-play session
        // never hits the end of the accumulated queue cold.
        let shown = usesOldestPages ? oldestEpisodes : allEpisodes
        let idx = shown.firstIndex(where: { $0.id == currentEpisode.id }) ?? 0
        if idx >= max(shown.count - 5, 0) {
            await loadNextPage(client: client)
        }
    }

    /// Oldest-first pages are needed only while the newest-first list is incomplete.
    private var usesOldestPages: Bool { episodeSort == .oldest && !reachedEnd }

    /// Called when the sort changes (and after a load): the first oldest-first page is fetched
    /// from the server instead of reversing the newest pages loaded so far.
    func sortChanged(client: KimaAPIClient) async {
        guard usesOldestPages, oldestEpisodes.isEmpty else { return }
        await loadNextOldestPage(client: client)
    }

    private func loadNextOldestPage(client: KimaAPIClient) async {
        guard !oldestReachedEnd, !isLoadingOldestPage, mode.isSubscribedMode else { return }
        isLoadingOldestPage = true
        defer { isLoadingOldestPage = false }
        do {
            let page = try await client.getPodcastEpisodesPage(
                id: activeId, limit: 200, offset: oldestEpisodes.count, oldestFirst: true)
            let seen = Set(oldestEpisodes.map(\.id))
            oldestEpisodes.append(contentsOf: page.episodes.filter { !seen.contains($0.id) })
            // A server without `order` support answers newest-first; sorting keeps the list oldest-first.
            oldestEpisodes.sort { ($0.publishedAt, $0.id) < ($1.publishedAt, $1.id) }
            episodeTotal = page.total
            oldestReachedEnd = oldestEpisodes.count >= page.total || page.episodes.isEmpty
        } catch {
            // Non-fatal: the list keeps what it has; the Load More button retries.
        }
    }

    private func loadAsPreview(itunesId: String, client: KimaAPIClient) async {
        do {
            let preview = try await client.getPodcastPreview(itunesId: itunesId)
            if preview.isSubscribed, let pid = preview.subscribedPodcastId {
                // Transparent redirect: podcast was already subscribed under a Kima ID.
                do {
                    let podcast = try await client.getPodcast(id: pid)
                    activeId = pid
                    seed(from: podcast)
                    mode = .subscribed(podcast)
                    fetchSimilar(podcastId: pid, client: client)
                } catch {
                    // Redirect failed; show preview with subscribe CTA.
                    mode = .preview(preview)
                }
            } else {
                mode = .preview(preview)
                fetchPreviewSimilar(itunesId: itunesId, client: client)
            }
        } catch {
            mode = .error("couldn't load podcast. check your connection.")
        }
    }

    private func fetchPreviewSimilar(itunesId: String, client: KimaAPIClient) {
        Task { [weak self] in
            guard let self else { return }
            do { similar = try await client.getPreviewSimilarPodcasts(itunesId: itunesId) } catch {}
        }
    }

    private func fetchSimilar(podcastId: String, client: KimaAPIClient) {
        Task { [weak self] in
            guard let self else { return }
            do { similar = try await client.getSimilarPodcasts(id: podcastId) } catch {}
        }
    }

    // MARK: - Pull-to-refresh

    /// GET /api/podcasts/:id/refresh (the server checks the feed for new episodes), then re-fetches detail and
    /// re-seeds the paging accumulators. `seed` resets allEpisodes, episodeTotal, reachedEnd and the oldest-first
    /// pages together, so accumulated pages are REPLACED — never appended to a stale list. Throws so the view can
    /// say the refresh failed; on throw the previous state is untouched. Preview mode is a no-op.
    func refresh(client: KimaAPIClient) async throws {
        guard case .subscribed = mode else { return }
        _ = try await client.refreshPodcast(id: activeId)
        let updated = try await client.getPodcast(id: activeId)
        seed(from: updated)
        mode = .subscribed(updated)
        await sortChanged(client: client)
    }

    // MARK: - Unsubscribe

    /// DELETE /api/podcasts/:id/unsubscribe.
    /// Throws on failure so the caller (view) can show a toast.
    func unsubscribe(client: KimaAPIClient) async throws {
        try await client.unsubscribePodcast(id: activeId)
    }

    // MARK: - Subscribe from preview

    /// POST /api/podcasts/subscribe with feedUrl + optional itunesId.
    /// Transitions mode to `.subscribed` on success.
    /// Returns the new Kima podcast ID for optional nav use.
    func subscribe(feedUrl: String, itunesId: String?, client: KimaAPIClient) async throws -> String? {
        isSubscribing = true
        defer { isSubscribing = false }
        let result = try await client.subscribePodcast(feedUrl: feedUrl, itunesId: itunesId)
        if let podcastId = result.podcast?.id {
            activeId = podcastId
            let podcast = try await client.getPodcast(id: podcastId)
            seed(from: podcast)
            mode = .subscribed(podcast)
            fetchSimilar(podcastId: podcastId, client: client)
            await sortChanged(client: client)
            return podcastId
        }
        return nil
    }

    // MARK: - Episode actions

    /// Optimistically marks the episode complete, then POSTs progress; reverts on failure.
    /// Rollback splices only the touched episode back — restoring a whole pre-action
    /// snapshot would discard pages the paging accumulator loaded during the await.
    func markEpisodeComplete(episode: Episode, client: KimaAPIClient) async {
        let optimisticProgress = EpisodeProgress(currentTime: episode.duration, progress: 100.0, isFinished: true)
        await applyProgress(optimisticProgress, to: episode) { podcast in
            _ = try await client.saveEpisodeProgress(
                podcastId: podcast.id, episodeId: episode.id,
                currentTime: episode.duration, duration: episode.duration, isFinished: true
            )
        }
    }

    /// Optimistically clears progress, then DELETEs it server-side; reverts on failure.
    /// Rollback splices only the touched episode (see markEpisodeComplete's note).
    func deleteEpisodeProgress(episode: Episode, client: KimaAPIClient) async {
        await applyProgress(nil, to: episode) { podcast in
            try await client.deleteEpisodeProgress(podcastId: podcast.id, episodeId: episode.id)
        }
    }

    /// Shows `progress` on the episode at once, runs `save`, and puts the episode back if `save` throws.
    private func applyProgress(_ progress: EpisodeProgress?, to episode: Episode,
                               save: (Podcast) async throws -> Void) async {
        guard case .subscribed(let podcast) = mode else { return }
        let previous = (allEpisodes + oldestEpisodes).first { $0.id == episode.id }
        replaceEpisode(id: episode.id) { $0.withProgress(progress) }
        mode = .subscribed(podcast.updatingEpisode(id: episode.id) { $0.withProgress(progress) })
        do {
            try await save(podcast)
        } catch {
            if let previous {
                replaceEpisode(id: previous.id) { _ in previous }
                if case .subscribed(let current) = mode { mode = .subscribed(current.updatingEpisode(id: episode.id) { _ in previous }) }
            }
        }
    }

    /// Applies an episode change to both accumulators.
    private func replaceEpisode(id: String, _ change: (Episode) -> Episode) {
        allEpisodes = allEpisodes.map { $0.id == id ? change($0) : $0 }
        oldestEpisodes = oldestEpisodes.map { $0.id == id ? change($0) : $0 }
    }

    /// True once every episode of the shown sort is loaded.
    var allLoaded: Bool { usesOldestPages ? oldestReachedEnd : reachedEnd }

    /// "Load more" visibility: true while server episodes remain un-accumulated.
    var canLoadMore: Bool { !allLoaded && mode.isSubscribedMode }

}
