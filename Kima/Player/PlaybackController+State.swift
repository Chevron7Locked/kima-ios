import AVFoundation
import Foundation

extension PlaybackController {

    // MARK: - Derived queue state

    /// Derived from `queue[currentIndex]`. Nil when queue is empty.
    var currentTrack: Track? {
        guard !queue.isEmpty, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    /// True when `bookId` is the audiobook loaded in the player, playing or paused.
    func isAudiobookLoaded(_ bookId: String) -> Bool {
        if case .audiobook(let session) = playbackType { return session.bookId == bookId }
        return false
    }

    // MARK: - Forwarding computed properties

    /// Mirrors `engine.isPlaying`. SwiftUI observation tracks through to the engine.
    var isPlaying: Bool        { engine.isPlaying }
    var engineStatus: EngineStatus { engine.status }
    var isBuffering: Bool      { engine.isBuffering }
    var audioError: String?    { engine.audioError }
    /// Play was asked for and no audio has come yet (loading or buffering); a tap now pauses.
    var isWaitingForAudio: Bool { engine.isWaitingForAudio }

    /// Current playback position in display units.
    /// Music / podcasts: engine time (file-relative seconds).
    /// Audiobooks: book-absolute seconds (file.startOffset + engine time).
    var currentTime: Double {
        switch playbackType {
        case .audiobook(let session):
            guard let file = session.fileByIndex(currentLongFormFileIndex) else {
                return engine.currentTime
            }
            return file.startOffset + engine.currentTime
        case .podcastEpisode, .track:
            return engine.currentTime
        }
    }

    /// Total duration in display units.
    /// Music: AVPlayerItem duration, or the track's own length until the stream has loaded (a
    /// restored queue, a load in flight). Audiobooks: book total. Podcasts: episode duration.
    var duration: Double {
        switch playbackType {
        case .audiobook(let session):
            return session.totalDuration
        case .podcastEpisode(_, let episode, _):
            return episode.duration
        case .track:
            return engine.duration > 0 ? engine.duration : (currentTrack?.duration ?? 0)
        }
    }

    /// True when either a music track or long-form content is loaded.
    /// Used by remote-command handlers instead of `currentTrack != nil` so audiobook/podcast
    /// lock-screen controls respond correctly when there is no `currentTrack` object.
    var isActive: Bool {
        currentTrack != nil || playbackType.isLongForm
    }

    /// A queue is committed and its first item is still being fetched: the tap happened, the
    /// player is working, and the UI must say so. `isActive` cannot answer this — it needs
    /// `currentTrack`, which only exists once the stream lands, so every play had a window with
    /// no feedback at all (the card's spinner had already gone; the mini player was not allowed).
    var isPreparingPlayback: Bool {
        !isActive && !queue.isEmpty && (engineStatus == .loading || engineStatus == .buffering)
    }

    /// The item that will play, whether or not it has loaded: the loaded track, else the queue
    /// position the player is pointed at. Lets the mini player name the track the moment the
    /// user taps, rather than after the network agrees.
    var upcomingTrack: Track? {
        if let currentTrack { return currentTrack }
        guard queue.indices.contains(currentIndex) else { return queue.first }
        return queue[currentIndex]
    }

    /// True when seeking is available: an item is loaded, or a music track is queued but not yet
    /// loaded (a restored queue — the seek sets where play starts). False while loading or in an
    /// error state — the waveform scrubber then disables interaction and shows a muted visual.
    var canSeek: Bool {
        switch engineStatus {
        case .idle: return !playbackType.isLongForm && currentTrack != nil
        case .loading, .error: return false
        default: return true
        }
    }

    /// Nothing is loaded, so a queue saved on the server (the last session, another device) can be shown.
    var canAdoptServerQueue: Bool { queue.isEmpty && engineStatus == .idle }

    /// Download progress 0–1 for progressive downloads. Always nil for live streaming.
    /// Reserved for offline/download mode (M-later); the waveform scrubber renders a
    /// secondary lighter fill for this range when non-nil.
    var downloadProgress: Double? { nil }

    // MARK: - Server hydration

    /// Apply a server-saved queue/index/shuffle state without loading the engine or autoplaying.
    /// Does not call `syncHook` (a server-applied state must not be re-saved: poll, apply, save, echo loop) and
    /// does not call `loadCurrentTrack`; the stream URL is built on the first resume gesture.
    /// Does nothing if there is already an active queue or a non-idle engine.
    func hydrateFromServer(queue: [Track], currentIndex: Int, isShuffle: Bool) {
        guard !queue.isEmpty, canAdoptServerQueue else { return }

        endStation()   // a queue from another device is not this device's station
        self.queue = queue
        let clamped = max(0, min(currentIndex, queue.count - 1))
        self.currentIndex = clamped
        self.isShuffle = isShuffle

        if isShuffle {
            shuffleOrder = buildShuffleOrder(keeping: clamped, total: queue.count)
            shufflePosition = 0
        } else {
            shuffleOrder = []
            shufflePosition = 0
        }

        // Update the lock screen with the restored track identity (shows paused, no URL loaded).
        // syncHook is intentionally NOT called here.
        nowPlayingHook?()
        hydrateCurrentTrackCoverIfNeeded()  // a restored queue can also lack album metadata
    }

    // MARK: - Detail hydration (artist + cover)

    /// Some queue shapes (library-shuffle, album-detail, some playlists) lack a top-level `artist` or
    /// `album.coverArt`, so the mini player would show "unknown artist". This fills the track from
    /// `GET /library/tracks/:id`; successes are cached by id, failures are not. Transient errors retry twice
    /// while the track is current; a 404 does not.
    func hydrateCurrentTrackCoverIfNeeded() {
        guard !playbackType.isLongForm else { return }   // long-form art is handled separately
        guard let track = currentTrack, !Self.isFilled(track) else { return }
        if let full = hydratedTracks[track.id] {
            spliceHydrated(full)                          // known fill — no refetch
            return
        }
        guard !hydrationInFlight.contains(track.id), let client = apiClient else { return }

        let trackId = track.id
        hydrationInFlight.insert(trackId)
        Task { @MainActor [weak self] in
            var full: Track?
            for attempt in 0..<3 {
                if attempt > 0 {
                    try? await Task.sleep(for: .seconds(attempt == 1 ? 1 : 3))
                    // Only keep retrying while this track is still the one on screen.
                    guard let self, self.currentTrack?.id == trackId else { break }
                }
                do {
                    full = try await client.getTrack(id: trackId)
                    break
                } catch APIError.http(let status, _) where status == 404 {
                    break                                 // gone server-side — nothing to fill
                } catch {
                    continue                              // transient — retry
                }
            }
            guard let self else { return }
            self.hydrationInFlight.remove(trackId)        // done either way; a miss retries next load
            guard let full, Self.hasArtist(full) || Self.hasCover(full) else { return }
            self.hydratedTracks[trackId] = full
            self.spliceHydrated(full)
        }
    }

    /// Replace every queued copy of `full.id` that `full` would fill (matched by id, not index —
    /// the queue may have moved or been replaced during the fetch), then nudge the lock screen.
    private func spliceHydrated(_ full: Track) {
        var changed = false
        for idx in queue.indices where queue[idx].id == full.id {
            let elem = queue[idx]
            let fillsArtist = !Self.hasArtist(elem) && Self.hasArtist(full)
            let fillsCover = !Self.hasCover(elem) && Self.hasCover(full)
            guard fillsArtist || fillsCover else { continue }
            queue[idx] = full                             // @Observable → mini + full player re-render
            changed = true
        }
        if changed { nowPlayingHook?() }
    }

    private static func hasArtist(_ t: Track) -> Bool { t.artist?.name.map { !$0.isEmpty } ?? false }
    private static func hasCover(_ t: Track) -> Bool { t.album?.coverArt.map { !$0.isEmpty } ?? false }
    private static func isFilled(_ t: Track) -> Bool { hasArtist(t) && hasCover(t) }
}
