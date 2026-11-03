import Foundation

// MARK: - PodcastDetailMode

/// Discriminates the two loading paths for PodcastDetailView.
/// `.subscribed` → full detail via GET /api/podcasts/:id.
/// `.preview`    → read-only preview via GET /api/podcasts/preview/:itunesId.
enum PodcastDetailMode: Sendable {
    case loading
    case subscribed(Podcast)
    case preview(PodcastPreview)
    case error(String)

    var isSubscribedMode: Bool {
        if case .subscribed = self { return true }
        return false
    }
}

// MARK: - PodcastEpisodeSort

enum PodcastEpisodeSort: String, CaseIterable, Sendable {
    case newest, oldest

    var label: String {
        switch self {
        case .newest: return "newest"
        case .oldest: return "oldest"
        }
    }
}

// MARK: - PodcastEpisodeFilter

/// Progress-state filter for the episode list: chips sit under the "episodes" header like the web list;
/// counts are computed on the accumulated pages, so "All" may read "+N more loading" while paging.
enum PodcastEpisodeFilter: String, CaseIterable, Sendable {
    case all, unplayed, inProgress, finished

    var label: String {
        switch self {
        case .all: return "all"
        case .unplayed: return "unplayed"
        case .inProgress: return "in progress"
        case .finished: return "finished"
        }
    }

    /// Classify an episode against this filter. Progress nil/zero = unplayed.
    func matches(_ ep: Episode) -> Bool {
        switch self {
        case .all: return true
        case .unplayed: return (ep.progress?.currentTime ?? 0) == 0 && ep.progress?.isFinished != true
        case .inProgress: return (ep.progress?.currentTime ?? 0) > 0 && ep.progress?.isFinished != true
        case .finished: return ep.progress?.isFinished == true
        }
    }
}
