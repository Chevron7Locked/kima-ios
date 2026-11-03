import Foundation

// MARK: - PodcastDetailViewModel · episode lists
// What the page lists, read from every loaded page (not page 1 alone): the shown sort, the filtered rows with
// season headers, the episodes in progress and the one "play latest" starts.

extension PodcastDetailViewModel {

    /// Episodes in the shown sort. .newest = the newest-first pages. .oldest = the reversed list once
    /// every episode is loaded, else the oldest-first pages fetched from the server.
    func sortedEpisodes() -> [Episode] {
        switch episodeSort {
        case .newest: return allEpisodes
        case .oldest: return reachedEnd ? allEpisodes.reversed() : oldestEpisodes
        }
    }

    /// Display rows for the list: filtered by the chip, then grouped into season runs with a
    /// header label on the first row of each run. One linear pass — the lazy list must not
    /// re-scan per row. Season nil = no header (one continuous show).
    func displayRows(from episodes: [Episode], filter: PodcastEpisodeFilter) -> [(episode: Episode, seasonHeader: String?)] {
        let shown = episodes.filter { filter.matches($0) }
        var out: [(episode: Episode, seasonHeader: String?)] = []
        out.reserveCapacity(shown.count)
        var i = 0
        while i < shown.count {
            let s = shown[i].season
            var j = i + 1
            while j < shown.count, shown[j].season == s { j += 1 }
            let label = s.map { "season \($0) · \(j - i)" }
            out.append((shown[i], label))
            for k in (i + 1)..<j { out.append((shown[k], nil)) }
            i = j
        }
        return out
    }

    /// In-progress episodes for the "continue listening" vertical stack.
    func continueListening() -> [Episode] {
        allEpisodes.filter {
            ($0.progress?.currentTime ?? 0) > 0 && $0.progress?.isFinished != true
        }
    }

    /// Play Latest: first unfinished episode (newest order), or episode[0] as fallback.
    func playLatestEpisode() -> Episode? {
        allEpisodes.first(where: { $0.progress?.isFinished != true })
            ?? allEpisodes.first
    }
}
