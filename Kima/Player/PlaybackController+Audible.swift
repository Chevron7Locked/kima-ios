import Foundation

// MARK: - PlaybackController audible derivation (ADR 0001)
//
// The one place play/pause display is derived. Audible = the engine is playing or fetching sound;
// session identity only scopes *which* item reads as current, never instead of it (ADR 0001).
// Pages ask these — they must not recompute from `playbackType` or `currentTrack` by hand.

extension PlaybackController {

    /// Main playback is putting out sound or fetching bytes to do so — the engine's truth every
    /// display read keys on (ADR 0001). Bounded by the stall watchdog, so it is safe to show.
    var isAudibleNow: Bool { isPlaying || isWaitingForAudio }

    /// How a track's control reads: `.playing` while audible, `.current` while it holds the
    /// session paused, `.none` otherwise.
    func displayState(of trackId: String) -> NowPlaying {
        guard currentTrack?.id == trackId else { return .none }
        return isAudibleNow ? .playing : .current
    }

    /// Whether something audible belongs to the page's content — the hero / grid-card question.
    /// The predicate states the page's own membership rule (album id, artist id + name fallback,
    /// playlist ids); the controller owns what *audible* means.
    func isAudible(where isIn: (Track) -> Bool) -> Bool {
        guard isAudibleNow, let currentTrack else { return false }
        return isIn(currentTrack)
    }

    /// The predicate form for a page whose membership is a track-id set (playlist / album hero):
    /// the page hands over its ids, never computes audibility itself.
    func isAudible(trackIds: Set<String>) -> Bool {
        isAudible { trackIds.contains($0.id) }
    }

    /// Whether one of `trackIds` holds the current session — dispatch only (resume vs start
    /// over), never a light (ADR 0001). The owns-session question for a track-id-set page.
    func ownsSession(forTrackIds trackIds: Set<String>) -> Bool {
        guard let id = currentTrack?.id else { return false }
        return trackIds.contains(id)
    }

    /// Whether this audiobook is what main playback has sound from — the card / detail question.
    func isAudible(bookId: String) -> Bool {
        guard isAudibleNow, case .audiobook(let session) = playbackType else { return false }
        return session.bookId == bookId
    }

    /// The episode main playback has sound from, when a podcast episode is doing it — the row
    /// light (build 20): nil while paused, so nothing claims playback.
    var audiblePodcastEpisodeId: String? {
        guard isAudibleNow, case .podcastEpisode(_, let episode, _) = playbackType else { return nil }
        return episode.id
    }

    /// Whether this show holds the current podcast session — dispatch only (resume vs play
    /// latest), never a light (ADR 0001).
    func ownsPodcastSession(_ podcastId: String) -> Bool {
        if case .podcastEpisode(let pid, _, _) = playbackType { return pid == podcastId }
        return false
    }
}
