import Foundation

// MARK: - Podcast (verbatim from the server's types)

struct Podcast: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let author: String
    let description: String?
    /// `/podcasts/:id/cover` when cached locally, or original URL, or nil.
    /// Optional because `imageUrl` can be null in the Prisma schema.
    let coverUrl: String?
    let autoDownloadEpisodes: Bool
    let genres: [String]?
    let feedUrl: String?
    /// Embedded episodes array (no separate episodes endpoint).
    /// List endpoint (GET /podcasts) returns latest 5; detail (GET /podcasts/:id) returns
    /// FIRST PAGE only (50, newest-first) + episodeTotal; later pages come from GET /podcasts/:id/episodes.
    let episodes: [Episode]
    // Backend also returns these; not in spec verbatim model but decoded when present
    let episodeCount: Int?
    let isSubscribed: Bool?
    /// Total episodes server-side (detail + /episodes paged responses). The list is paginated;
    /// this is the full catalogue count — the "176 of N" header and paging accumulator's target.
    let episodeTotal: Int?
    /// When the show last published (GET /podcasts list only), ISO 8601.
    var latestEpisodeAt: String? = nil
    /// Apple categories the show carries (GET /podcasts/:id only).
    var categories: [PodcastCategoryRef]? = nil
}

// MARK: - EpisodePage (GET /podcasts/:id/episodes — paged, desc, prod 047e4726)

/// Decoded page from the paging endpoint: `{episodes, total}`.
/// limit clamps to 200, default 50; offset is episode count.
struct EpisodePage: Codable, Sendable {
    let episodes: [Episode]
    let total: Int

    private enum CodingKeys: String, CodingKey { case episodes, total }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        episodes = try c.decode([Episode].self, forKey: .episodes)
        // Tolerate a server that omits `total`: the response is the complete list.
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? episodes.count
    }
}

// MARK: - Episode

struct Episode: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let description: String?
    let duration: Double           // seconds
    let publishedAt: String        // ISO 8601 — kept as String per spec + web types
    let episodeNumber: Int?
    let season: Int?
    let progress: EpisodeProgress?
    // Backend detail response also includes these fields
    let imageUrl: String?
    let isDownloaded: Bool?
    // Backend search results include audioUrl for direct streaming
    let audioUrl: String?
}

// MARK: - EpisodeProgress

/// Progress entry embedded in Episode.
typealias EpisodeProgress = LongFormProgress

// MARK: - PodcastPreview (verbatim from the server's types)

/// Returned by GET /api/podcasts/preview/:itunesId — a show not followed yet, from Apple's record and its feed.
struct PodcastPreview: Codable, Sendable {
    let title: String
    let author: String
    let description: String?
    let coverUrl: String?
    let genres: [String]?
    let feedUrl: String?
    let itunesId: String?
    let isSubscribed: Bool
    /// If `isSubscribed` is true, redirect to this podcast's full detail page.
    let subscribedPodcastId: String?
    let episodeCount: Int?
    let previewEpisodes: [PreviewEpisode]?
    let categories: [PodcastCategoryRef]?
    /// The first episode, playable as a sample; nil when the feed has none or did not answer.
    let snippet: PodcastSnippet?
}

// MARK: - PreviewEpisode (verbatim from the server's types)

struct PreviewEpisode: Codable, Sendable {
    let title: String
    let publishedAt: String        // ISO 8601 string
    let duration: Double
    let description: String?
}

// MARK: - DiscoveryPodcast

/// A show from Apple's charts (`DiscoveryItem`: /charts, /for-you, /similar, /discover/*).
/// `itunesId` is a string on current servers (a number is accepted too).
/// These are NOT subscribed podcasts — they navigate to a preview or subscribe flow.
struct DiscoveryPodcast: Identifiable, Codable, Sendable {
    let id: String             // the Apple id
    let title: String
    let author: String
    let coverUrl: String?
    let feedUrl: String?
    let genres: [String]?
    let episodeCount: Int?
    let itunesId: String?
    let isExternal: Bool?
    let description: String?
    let categoryIds: [Int]?
    /// Position on the chart it came from; nil off a chart.
    let chartRank: Int?

    private enum CodingKeys: String, CodingKey {
        case id, title, author, coverUrl, feedUrl, genres, episodeCount, itunesId, isExternal
        case description, categoryIds, chartRank
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        author = try c.decode(String.self, forKey: .author)
        coverUrl = try c.decodeIfPresent(String.self, forKey: .coverUrl)
        feedUrl = try c.decodeIfPresent(String.self, forKey: .feedUrl)
        genres = try c.decodeIfPresent([String].self, forKey: .genres)
        episodeCount = try c.decodeIfPresent(Int.self, forKey: .episodeCount)
        isExternal = try c.decodeIfPresent(Bool.self, forKey: .isExternal)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        categoryIds = try c.decodeIfPresent([Int].self, forKey: .categoryIds)
        chartRank = try c.decodeIfPresent(Int.self, forKey: .chartRank)
        if let s = try? c.decodeIfPresent(String.self, forKey: .itunesId) {
            itunesId = s
        } else if let n = try? c.decodeIfPresent(Int.self, forKey: .itunesId) {
            itunesId = String(n)
        } else {
            itunesId = nil
        }
    }
}

// MARK: - Response shapes

/// POST /api/podcasts/subscribe response.
struct SubscribeResponse: Codable, Sendable {
    let success: Bool
    let podcast: PodcastStub?
    let message: String?

    struct PodcastStub: Codable, Sendable {
        let id: String
        let title: String
    }
}

/// GET /api/podcasts/:id/refresh response.
struct PodcastRefreshResult: Codable, Sendable {
    let success: Bool
    let newEpisodesCount: Int
    let totalEpisodes: Int
    let message: String?
}

/// POST /api/podcasts/refresh-all response.
struct PodcastRefreshAllResponse: Codable, Sendable {
    let queued: Int
    let total: Int?
    let message: String?
}

/// POST /api/podcasts/:podcastId/episodes/:episodeId/progress response.
struct EpisodeProgressResponse: Codable, Sendable {
    let success: Bool
    let progress: ProgressBody?

    struct ProgressBody: Codable, Sendable {
        let currentTime: Double
        let progress: Double
        let isFinished: Bool
    }
}

// MARK: - Optimistic update helpers

extension Episode {
    func withProgress(_ p: EpisodeProgress?) -> Episode {
        Episode(
            id: id, title: title, description: description, duration: duration,
            publishedAt: publishedAt, episodeNumber: episodeNumber, season: season,
            progress: p, imageUrl: imageUrl, isDownloaded: isDownloaded, audioUrl: audioUrl
        )
    }
}

extension Podcast {
    func updatingEpisode(id episodeId: String, transform: (Episode) -> Episode) -> Podcast {
        let updated = episodes.map { $0.id == episodeId ? transform($0) : $0 }
        return Podcast(
            id: id, title: title, author: author, description: description,
            coverUrl: coverUrl, autoDownloadEpisodes: autoDownloadEpisodes,
            genres: genres, feedUrl: feedUrl, episodes: updated,
            episodeCount: episodeCount, isSubscribed: isSubscribed,
            episodeTotal: episodeTotal, latestEpisodeAt: latestEpisodeAt, categories: categories
        )
    }
}
