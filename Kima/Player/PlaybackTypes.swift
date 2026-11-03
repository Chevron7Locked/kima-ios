import Foundation

// MARK: - LongFormPlaybackType

/// Discriminates what the player is currently playing so views and engine logic can branch.
/// `.track` is the default (music); `.audiobook` / `.podcastEpisode` are long-form types.
enum LongFormPlaybackType: Sendable {
    case track
    case audiobook(BookSession)
    case podcastEpisode(podcastId: String, episode: Episode, queue: [Episode])

    /// True for any long-form type (audiobook or podcast).
    var isLongForm: Bool {
        if case .track = self { return false }
        return true
    }

    /// True only for audiobooks (shuffle/next/prev disabled).
    var isAudiobook: Bool {
        if case .audiobook = self { return true }
        return false
    }
}

// MARK: - RepeatMode

/// Cycles off → all → one. Track-type only; audiobooks and podcasts do not use repeat
enum RepeatMode: String, CaseIterable, Sendable {
    case off
    case all
    case one

    /// Advance to the next mode in the cycle.
    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    /// SF Symbol for the current mode. `off` and `all` share the base repeat glyph;
    /// the caller dims `off` to indicate the control is inactive.
    var systemImage: String {
        switch self {
        case .off, .all: return "repeat"
        case .one:       return "repeat.1"
        }
    }
}

// MARK: - EngineStatus

/// Observable playback engine state. Maps AVFoundation events to user-visible semantics.
///
/// `recovering` from the web engine is omitted: AVPlayer buffers by itself, and a stream that stops
/// is rebuilt by the stall watchdog (`PlaybackEngine+Stall.swift`) through the controller's recovery.
enum EngineStatus: Sendable, Equatable {
    /// No item loaded; AVPlayer has no current item.
    case idle
    /// Item is loading; waiting for `AVPlayerItem.status == .readyToPlay`.
    case loading
    /// `player.timeControlStatus == .playing`.
    case playing
    /// `player.timeControlStatus == .waitingToPlayAtSpecifiedRate` (stall or initial buffer).
    case buffering
    /// User or system pause; intent is preserved for foreground/route auto-resume.
    case paused
    /// Interruption ended without `.shouldResume` — show tap-to-play affordance, never
    /// auto-resume. The interruption handler sets this.
    case blocked
    /// `AVPlayerItem.status == .failed`. `PlaybackEngine.audioError` carries the message.
    case error
}
