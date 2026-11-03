import Foundation
import MediaPlayer
import UIKit

/// Owns `MPNowPlayingInfoCenter` (lock screen metadata) and `MPRemoteCommandCenter` (headphone / lock-screen
/// controls). `@MainActor`; remote-command handlers fire on a system queue and hop to the main actor first.
/// Elapsed time is pushed at most every 5 s during playback, immediately on user actions. Artwork is fetched
/// once per item; a failed or cancelled download leaves none and is not retried.
@MainActor
final class NowPlayingController {

    // MARK: - Dependencies

    /// Internal (no access modifier) so `NowPlayingController+RemoteCommands.swift` can read it
    /// across the file boundary — same cross-file-extension pattern `PlaybackController` uses.
    weak var controller: PlaybackController?
    private let server: KimaServer

    // MARK: - Artwork

    /// Cover art for the currently-playing item. Single image — bounded by definition.
    /// Cleared on item change; populated by fetchArtwork (which delegates storage to
    /// ImageCache.shared so the image survives across NowPlayingController lifetimes
    /// without this dict growing unboundedly).
    private var currentItemArtwork: UIImage?
    private var artworkFetchTask: Task<Void, Never>?

    /// Generic now-playing item ID whose artwork download was last initiated — a music
    /// track ID, an audiobook's `bookId`, or a podcast `episode.id`. Prevents re-fetching
    /// on every `refresh()` call for the same item.
    private var lastArtworkItemId: String?

    /// Cover ID last fetched for the lock screen. Keyed separately from `lastArtworkItemId`
    /// because a bare radio/shuffle track can be hydrated with its `album.coverArt` AFTER the
    /// first push — same track id, newly-available cover — and that must still trigger a fetch.
    private var lastArtworkCoverId: String?

    // MARK: - Position throttle

    /// Monotonic timestamp of the last `ElapsedPlaybackTime` push (CACurrentMediaTime).
    private var lastPositionPushTime: CFTimeInterval = 0

    // MARK: - Init

    init(controller: PlaybackController, server: KimaServer) {
        self.controller = controller
        self.server = server
        registerRemoteCommands()
    }

    // MARK: - Refresh

    /// Rebuild and push `MPNowPlayingInfoCenter.nowPlayingInfo` from the controller's state. Safe to call often.
    /// - Parameter isUserAction: `true` for play/pause/seek/skip/track change: always pushes `ElapsedPlaybackTime`
    ///   and resets the throttle. `false` for the 1 Hz tick: pushes position only after 5 s.
    func refresh(isUserAction: Bool = false) {
        guard let controller else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState  = .stopped
            return
        }

        // update remote-command skip intervals based on current playback type.
        let rc = MPRemoteCommandCenter.shared()
        if controller.playbackType.isLongForm {
            rc.skipForwardCommand.preferredIntervals  = [30]
            rc.skipBackwardCommand.preferredIntervals = [30]
            rc.nextTrackCommand.isEnabled     = false
            rc.previousTrackCommand.isEnabled = false
            rc.changePlaybackRateCommand.isEnabled = true
        } else {
            rc.skipForwardCommand.preferredIntervals  = [15]
            rc.skipBackwardCommand.preferredIntervals = [15]
            rc.nextTrackCommand.isEnabled     = true
            rc.previousTrackCommand.isEnabled = true
            rc.changePlaybackRateCommand.isEnabled = false
        }

        // handle long-form (no currentTrack — metadata comes from longFormNowPlayingMeta).
        if controller.playbackType.isLongForm {
            guard let meta = controller.longFormNowPlayingMeta else {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                MPNowPlayingInfoCenter.default().playbackState  = .stopped
                return
            }
            // Generic item ID for the artwork cache key — a book's bookId or an episode's id.
            let itemId: String?
            switch controller.playbackType {
            case .audiobook(let session):             itemId = session.bookId
            case .podcastEpisode(_, let episode, _):  itemId = episode.id
            case .track:                              itemId = nil
            }
            buildAndPushInfo(
                title: meta.title, artist: meta.artist,
                albumTitle: nil, itemId: itemId, coverURL: meta.coverURL,
                duration: controller.duration,     // book total or episode duration
                currentTime: controller.currentTime,
                playbackRate: controller.playbackType.isAudiobook
                    ? Double(controller.audiobookSpeed)
                    : Double(controller.podcastSpeed),
                isPlaying: controller.isPlaying,
                isUserAction: isUserAction
            )
            return
        }

        guard let track = controller.currentTrack else {
            // No media loaded → clear the lock screen entirely.
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState  = .stopped
            return
        }

        let now        = CACurrentMediaTime()
        let isPlaying  = controller.isPlaying
        let currentTime = controller.currentTime
        let duration   = controller.duration

        // ── Metadata ──────────────────────────────────────────────────────────────────
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle]           = track.effectiveTitle
        if let name  = track.artist?.name  { info[MPMediaItemPropertyArtist]     = name  }
        if let title = track.album?.title  { info[MPMediaItemPropertyAlbumTitle] = title }
        info[MPMediaItemPropertyPlaybackDuration]         = duration
        // A non-zero `PlaybackRate` makes the system advance the lock-screen / CarPlay time between pushes, and our
        // 1 Hz re-push then snaps it back (a jumping scrubber while paused; `playbackState = .paused` alone does
        // not freeze it). So zero the rate on pause. `DefaultPlaybackRate` stays 1.0 as the speed button's label.
        info[MPNowPlayingInfoPropertyPlaybackRate]        = NSNumber(value: isPlaying ? 1.0 : 0.0)
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = NSNumber(value: 1.0)

        // ── Position throttle ─────────────────────────────────────────────────────────
        // Push immediately on user actions or when paused (lock-screen scrubbing must be accurate). During
        // playback throttle to 5 s; the OS advances the display from the last push using the playbackRate.
        let shouldPushPosition = isUserAction
            || !isPlaying
            || (now - lastPositionPushTime >= 5.0)

        if shouldPushPosition {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            lastPositionPushTime = now
        } else {
            // Carry the existing elapsed time forward so we don't regress the display.
            if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo,
               let elapsed  = existing[MPNowPlayingInfoPropertyElapsedPlaybackTime] {
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            }
        }

        // ── Artwork ───────────────────────────────────────────────────────────────────
        // Keyed on the resolved coverId, not the track id: a bare radio/shuffle/vibe track is hydrated with its
        // cover later under the same id, and that must still trigger a fetch. On a real track change the cover
        // key is reset so art never carries across items.
        let coverId     = track.album?.coverArt
        let itemChanged = lastArtworkItemId != track.id
        if itemChanged {
            lastArtworkItemId  = track.id
            lastArtworkCoverId = nil
            currentItemArtwork = nil
            artworkFetchTask?.cancel()
        }
        let coverChanged = coverId != lastArtworkCoverId
        if coverChanged { currentItemArtwork = nil }   // stale / newly-available cover
        publish(info, isPlaying: isPlaying)

        if coverChanged {
            lastArtworkCoverId = coverId
            if let coverId, let url = CoverArtURL.url(base: server, coverId: coverId, size: 512) {
                fetchArtwork(from: url)
            }
        }
    }

    // MARK: - Long-form info push

    /// Build and push MPNowPlayingInfoCenter metadata for long-form content (audiobook or
    /// podcast episode). Artwork mirrors the music path below: patch-not-rebuild, keyed by
    /// `itemId`, fetched once per item via the shared `fetchArtwork(from:)`.
    private func buildAndPushInfo(
        title: String,
        artist: String,
        albumTitle: String?,
        itemId: String?,
        coverURL: URL?,
        duration: Double,
        currentTime: Double,
        playbackRate: Double,
        isPlaying: Bool,
        isUserAction: Bool
    ) {
        let now = CACurrentMediaTime()
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle]  = title
        info[MPMediaItemPropertyArtist] = artist
        if let albumTitle { info[MPMediaItemPropertyAlbumTitle] = albumTitle }
        info[MPMediaItemPropertyPlaybackDuration]         = duration
        // `PlaybackRate` drives the OS elapsed-time extrapolation: a non-zero rate while paused makes the
        // lock-screen scrubber drift forward and snap back on each 1 Hz re-push, so it is zeroed on pause.
        // `DefaultPlaybackRate` always carries the chosen speed; CarPlay's rate button renders it as its label.
        // The pause glyph comes from `playbackState` below.
        info[MPNowPlayingInfoPropertyPlaybackRate]        = NSNumber(value: isPlaying ? playbackRate : 0.0)
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = NSNumber(value: playbackRate)

        let shouldPushPosition = isUserAction || !isPlaying || (now - lastPositionPushTime >= 5.0)
        if shouldPushPosition {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            lastPositionPushTime = now
        } else if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo,
                  let elapsed  = existing[MPNowPlayingInfoPropertyElapsedPlaybackTime] {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }

        // ── Artwork ───────────────────────────────────────────────────────────────────
        // Mirrors the music branch: on item change, clear stale art and fetch; on same-item
        // refreshes, currentItemArtwork keeps the fetched image (guarded by itemChanged below).
        let itemChanged = lastArtworkItemId != itemId
        if itemChanged {
            currentItemArtwork = nil
            lastArtworkItemId  = itemId
        }
        publish(info, isPlaying: isPlaying)

        if itemChanged, let coverURL { fetchArtwork(from: coverURL) }
    }

    /// Hands `info` to the system with the current item's artwork, if it has loaded.
    private func publish(_ info: [String: Any], isPlaying: Bool) {
        var info = info
        if let image = currentItemArtwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: CGSize(width: 512, height: 512)
            ) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState  = isPlaying ? .playing : .paused
    }

    // MARK: - Artwork download

    /// Fetch cover art for the playing item from an already-resolved URL and patch it into the live now-playing
    /// dict when it lands, never a full rebuild. Callers resolve the URL (`CoverArtURL` for music/audiobook,
    /// `meta.coverURL` for long-form).
    private func fetchArtwork(from url: URL) {
        artworkFetchTask?.cancel()

        // ImageCache.shared dedups, caches and attaches the auth header for our server host. The decode runs off
        // the main actor; the continuation resumes here on @MainActor with the decoded image.
        artworkFetchTask = Task { [weak self] in
            do {
                let image = try await ImageCache.shared.fetch(url: url)
                guard !Task.isCancelled else { return }
                guard let self else { return }

                // Store on self so subsequent refresh() calls include artwork without a fetch.
                self.currentItemArtwork = image
                // Patch the lock screen without a full info rebuild.
                if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                        boundsSize: CGSize(width: 512, height: 512)
                    ) { _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            } catch {
                // Download failed or task was cancelled — no artwork, no crash.
            }
        }
    }
}
