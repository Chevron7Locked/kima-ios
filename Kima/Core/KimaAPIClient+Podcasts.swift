import Foundation

// MARK: - Private request payloads

private struct SubscribeBody: Encodable {
    let feedUrl: String
    let itunesId: String?
}

private struct EpisodeProgressPayload: Encodable {
    let currentTime: Double
    let duration: Double
    let isFinished: Bool
}


// MARK: - KimaAPIClient + Podcasts

extension KimaAPIClient {

    // MARK: Subscribed library

    /// GET /api/podcasts — the user's subscribed podcasts, each with its 5 most recent episodes (with progress).
    /// Use `getPodcast(id:)` for the full episode list.
    func getPodcasts() async throws -> [Podcast] {
        try await get("/podcasts", authed: true)
    }

    /// GET /api/podcasts/:id — one subscribed podcast with all episodes, newest first, including `progress`,
    /// `imageUrl` and `isDownloaded`. 404 if the user is not subscribed.
    func getPodcast(id: String) async throws -> Podcast {
        try await get("/podcasts/\(id)", authed: true)
    }

    /// GET /api/podcasts/:id/episodes?limit=N&offset=N — one page of `{episodes, total}`, newest first by default.
    /// `limit` is clamped to 1…200 (default 50), `offset` ≥ 0. `oldestFirst` sends `order=oldest`.
    func getPodcastEpisodesPage(id: String, limit: Int = 200, offset: Int = 0, oldestFirst: Bool = false) async throws -> EpisodePage {
        var query = ["limit": "\(limit)", "offset": "\(offset)"]
        if oldestFirst { query["order"] = "oldest" }
        return try await get("/podcasts/\(id)/episodes", query: query, authed: true)
    }

    // MARK: Discovery

    /// GET /api/podcasts/preview/:itunesId — preview a show not followed yet by its Apple id. If
    /// `preview.isSubscribed`, redirect to `preview.subscribedPodcastId`. A slow feed is cut off after 8 seconds and
    /// the preview answers from Apple's record alone.
    func getPodcastPreview(itunesId: String) async throws -> PodcastPreview {
        try await get("/podcasts/preview/\(KimaServer.pathSegment(itunesId))", authed: true)
    }

    /// GET /api/podcasts/:id/similar — shows on the charts of a followed show's categories; `[]` when none.
    func getSimilarPodcasts(id: String) async throws -> [DiscoveryPodcast] {
        try await get("/podcasts/\(KimaServer.pathSegment(id))/similar", authed: true)
    }

    /// GET /api/podcasts/preview/:itunesId/similar — shows on the charts of a not-followed show's categories.
    func getPreviewSimilarPodcasts(itunesId: String) async throws -> [DiscoveryPodcast] {
        try await get("/podcasts/preview/\(KimaServer.pathSegment(itunesId))/similar", authed: true)
    }

    // MARK: Charts and categories

    /// GET /api/podcasts/categories — Apple's whole category tree; top-level ones have `parentId == nil`.
    func getPodcastCategories() async throws -> [PodcastCategory] {
        try await get("/podcasts/categories", authed: true)
    }

    /// GET /api/podcasts/charts?category=&limit=&offset=&background= — one page of Apple's chart for a category,
    /// or the overall chart when `category` is nil. `limit` 1…200, `offset` 0…200; an unknown category is a 404.
    /// `background` queues the request behind ones a person is waiting on (rows below the fold).
    func getPodcastChart(category: Int?, limit: Int = 20, offset: Int = 0, background: Bool = false) async throws -> [DiscoveryPodcast] {
        var query = ["limit": "\(limit)", "offset": "\(offset)"]
        if let category { query["category"] = "\(category)" }
        if background { query["background"] = "true" }
        return try await get("/podcasts/charts", query: query, authed: true)
    }

    /// GET /api/podcasts/for-you — up to 3 rows of 12, built from the categories of the followed shows.
    func getPodcastsForYou() async throws -> [PodcastForYouRow] {
        try await get("/podcasts/for-you", authed: true)
    }

    /// GET /api/podcasts/listening — episodes in progress and new episodes across every followed show.
    func getPodcastListening() async throws -> PodcastListening {
        try await get("/podcasts/listening", authed: true)
    }

    /// GET /api/podcasts/:podcastId/episodes/:episodeId/next — the show's next unfinished episode by release date.
    func getNextEpisode(podcastId: String, episodeId: String) async throws -> PodcastNextEpisode {
        try await get(
            "/podcasts/\(KimaServer.pathSegment(podcastId))/episodes/\(KimaServer.pathSegment(episodeId))/next",
            authed: true
        )
    }

    // MARK: Subscribe / Unsubscribe

    /// POST /api/podcasts/subscribe (no `:id` segment) — subscribe via RSS feed URL or iTunes ID, body
    /// `{ feedUrl, itunesId? }`. Returns `{ success, podcast: { id, title }, message }`; navigate to `podcast.id`.
    @discardableResult
    func subscribePodcast(feedUrl: String, itunesId: String? = nil) async throws -> SubscribeResponse {
        let body = SubscribeBody(feedUrl: feedUrl, itunesId: itunesId)
        return try await postJSON("/podcasts/subscribe", body: body, authed: true)
    }

    /// DELETE /api/podcasts/:id/unsubscribe
    ///
    /// Unsubscribe from a podcast. Also deletes the user's progress for all episodes
    /// and any downloaded episodes. Should be preceded by a confirmation alert.
    func unsubscribePodcast(id: String) async throws {
        try await deleteChecked("/podcasts/\(id)/unsubscribe", authed: true)
    }

    // MARK: Refresh

    /// GET /api/podcasts/:id/refresh
    ///
    /// Refreshes a single podcast's feed, adding any new episodes.
    /// Returns `{ success, newEpisodesCount, totalEpisodes, message }`.
    func refreshPodcast(id: String) async throws -> PodcastRefreshResult {
        try await get("/podcasts/\(id)/refresh", authed: true)
    }

    /// POST /api/podcasts/refresh-all
    ///
    /// Queues background refresh jobs for all of the user's subscribed podcasts.
    /// Returns `{ queued, total, message }`.
    @discardableResult
    func refreshAllPodcasts() async throws -> PodcastRefreshAllResponse {
        try await postJSON("/podcasts/refresh-all", body: EmptyRequestBody(), authed: true)
    }

    // MARK: Episode progress

    /// POST /api/podcasts/:podcastId/episodes/:episodeId/progress
    ///
    /// Saves episode-absolute playback position. Call every 15 s while playing and on
    /// pause, background, and end of episode.
    @discardableResult
    func saveEpisodeProgress(
        podcastId: String,
        episodeId: String,
        currentTime: Double,
        duration: Double,
        isFinished: Bool
    ) async throws -> EpisodeProgressResponse {
        let payload = EpisodeProgressPayload(
            currentTime: currentTime,
            duration: duration,
            isFinished: isFinished
        )
        return try await postJSON(
            "/podcasts/\(podcastId)/episodes/\(episodeId)/progress",
            body: payload,
            authed: true
        )
    }

    /// DELETE /api/podcasts/:podcastId/episodes/:episodeId/progress
    ///
    /// Resets progress for an episode. Called from the episode list swipe action
    /// "Delete Progress" or the "Mark as Unplayed" action.
    func deleteEpisodeProgress(podcastId: String, episodeId: String) async throws {
        try await deleteChecked(
            "/podcasts/\(podcastId)/episodes/\(episodeId)/progress",
            authed: true
        )
    }
}
