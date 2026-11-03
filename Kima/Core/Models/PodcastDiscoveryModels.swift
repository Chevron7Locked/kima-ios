import Foundation

// Podcast discovery and listening shapes: categories, chart rows, for-you rows, the listening list, the next
// episode and the first-episode sample.

// MARK: - Categories

/// One of Apple's podcast categories from GET /api/podcasts/categories. Sub-categories name their parent.
struct PodcastCategory: Identifiable, Codable, Sendable, Hashable {
    let id: Int
    let name: String
    let parentId: Int?
}

/// A category a show carries (`categories` on a show page or preview).
struct PodcastCategoryRef: Identifiable, Codable, Sendable, Hashable {
    let id: Int
    let name: String
}

/// One row from GET /api/podcasts/for-you: a category's chart minus the shows already followed.
/// `because` names the followed shows that put the category here.
struct PodcastForYouRow: Decodable, Sendable, Identifiable {
    let category: PodcastCategory
    let because: [String]
    let podcasts: [DiscoveryPodcast]
    var id: Int { category.id }
}

// MARK: - Listening

/// GET /api/podcasts/listening — across every followed show: episodes in progress (most recently played
/// first, up to 12) and each show's newest episode while unplayed (newest first, up to 20).
struct PodcastListening: Decodable, Sendable {
    let inProgress: [PodcastListeningRow]
    let newEpisodes: [PodcastListeningRow]
}

/// The show an episode row or a next episode belongs to.
struct PodcastListeningShow: Decodable, Sendable, Hashable {
    let id: String
    let title: String
    let coverUrl: String?
}

/// An episode as the listening and next-episode routes send it.
struct PodcastListeningEpisode: Decodable, Sendable {
    let id: String
    let title: String
    let description: String?
    let duration: Double
    let publishedAt: String
    let coverUrl: String?
    let progress: EpisodeProgress?

    /// The app's `Episode`, for the player and the episode rows.
    var asEpisode: Episode {
        Episode(
            id: id, title: title, description: description, duration: duration,
            publishedAt: publishedAt, episodeNumber: nil, season: nil, progress: progress,
            imageUrl: coverUrl, isDownloaded: nil, audioUrl: nil
        )
    }
}

struct PodcastListeningRow: Decodable, Sendable, Identifiable {
    let podcast: PodcastListeningShow
    let episode: PodcastListeningEpisode
    var id: String { episode.id }
}

/// GET /api/podcasts/:podcastId/episodes/:episodeId/next — the show's next unfinished episode by release
/// date, or `episode: null` at the end of the show.
struct PodcastNextEpisode: Decodable, Sendable {
    let podcast: PodcastListeningShow?
    let episode: PodcastListeningEpisode?
}

// MARK: - Preview sample

/// The show's first episode, which GET /api/podcasts/preview/:itunesId/snippet streams without storing.
struct PodcastSnippet: Codable, Sendable {
    let title: String
    let publishedAt: String
    let duration: Double
}
