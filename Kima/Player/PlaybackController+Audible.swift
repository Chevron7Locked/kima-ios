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

    /// What the transport play/pause controls show for the current session — engine truth in
    /// display vocabulary, so glyph selection leaves the view bodies (ADR 0001).
    enum TransportDisplayState: Equatable {
        case playing
        case waiting
        case retry
        case blocked
        case paused
        case stopped

        /// The glyph for this state; nil while waiting — the circle renders a spinner there, so
        /// a fetch never reads as a resting play control.
        var systemImage: String? {
            switch self {
            case .playing: return "pause.fill"
            case .waiting: return nil
            case .retry:   return "arrow.clockwise"
            case .blocked, .paused, .stopped: return "play.fill"
            }
        }

        /// What a tap on the control honors — the label says exactly that (ADR 0001).
        var accessibilityLabel: String {
            switch self {
            case .playing, .waiting: return "pause"
            case .retry:             return "retry playback"
            case .blocked, .paused, .stopped: return "play"
            }
        }

        /// The play triangle, wherever it renders — the glyph that needs a rightward nudge for
        /// optical centering (the symbol name itself must not leak into view bodies).
        var showsPlayGlyph: Bool { systemImage == "play.fill" }

        /// VoiceOver value while fetching: the label stays honest, the state reads as loading.
        var accessibilityValue: String { self == .waiting ? "loading" : "" }
    }

    /// The one answer both transport controls render: pause while audible — sound out, or bytes on
    /// the way — the retry arrow over a dead item, and a fetch never shows the play glyph a tap
    /// would contradict (ADR 0001). Reads go in `togglePlayPause()`'s precedence (playing first) so
    /// display can never disagree with dispatch; every engine error path clears `isPlaying` before
    /// setting `.error`, so that order is an invariant, not a race. The silent tail names its
    /// resting kind so downstream surfaces (lock screen, ticket 03) map without touching engine
    /// mirrors.
    var transportDisplayState: TransportDisplayState {
        if isPlaying { return .playing }
        if engineStatus == .error { return .retry }
        if isWaitingForAudio { return .waiting }
        switch engineStatus {
        case .blocked: return .blocked
        case .paused:  return .paused
        default:       return .stopped
        }
    }

    /// How a track's control reads: `.playing` while audible, `.current` while it holds the
    /// session paused, `.none` otherwise.
    func displayState(of trackId: String) -> RowDisplayState {
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

    /// Whether the current session is one the page's content — dispatch only (resume vs start
    /// over), never a light (ADR 0001). The predicate states the page's own membership rule
    /// (artist: id-or-name fallback); the controller owns what *holds the session* means.
    func ownsSession(where isIn: (Track) -> Bool) -> Bool {
        guard let currentTrack else { return false }
        return isIn(currentTrack)
    }

    /// The predicate form for a page whose membership is a track-id set (playlist / album hero):
    /// the page hands over its ids, never computes ownership itself.
    func ownsSession(forTrackIds trackIds: Set<String>) -> Bool {
        ownsSession { trackIds.contains($0.id) }
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
