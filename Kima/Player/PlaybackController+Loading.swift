import AVFoundation
import Foundation

extension PlaybackController {

    // MARK: - Queue loading

    /// Primary play entry point: sets the queue and begins playback at `startAt` (default 0).
    /// `shuffle` overrides `isShuffle`; nil leaves it unchanged.
    func play(tracks: [Track], startAt startIndex: Int = 0, shuffle: Bool? = nil) {
        guard !tracks.isEmpty else { return }
        notePlayRequest()
        cancelSkipDebounce()  // a pending skip must not seek the new item
        stopLongForm()        // cancel any running long-form session + progress timer
        playbackType = .track // reset to music mode
        longFormNowPlayingMeta = nil
        queueOrigin = nil; vibeSimilarities = [:]  // a new queue ends any vibe queue (stopLongForm ends any station)
        // Restore music audio session mode (spokenAudio was set for long-form).
        engine.claimAudioSession(mode: .default)
        queue = tracks
        consecutiveErrorCount = 0
        resetRecoveryBudget()           // fresh playback → fresh recovery budget

        if let shuffle { isShuffle = shuffle }

        let clampedStart = max(0, min(startIndex, tracks.count - 1))
        if isShuffle {
            shuffleOrder = buildShuffleOrder(keeping: clampedStart, total: tracks.count)
            shufflePosition = 0
            currentIndex = clampedStart  // shuffleOrder[0] == clampedStart by construction
        } else {
            shuffleOrder = []
            shufflePosition = 0
            currentIndex = clampedStart
        }

        loadCurrentTrack(autoplay: true)
        nowPlayingHook?()
        syncHook?()        // new queue, index, shuffle all changed
    }

    // MARK: - URL building + item loading

    /// Load `queue[currentIndex]` into the engine (internal so +Queue.swift can call it after queue mutations).
    /// Mints (or reuses) a stream ticket in a Task, then loads unless a newer load claimed the player meanwhile.
    func loadCurrentTrack(autoplay: Bool, seekTo: Double? = nil) {
        guard !queue.isEmpty, queue.indices.contains(currentIndex) else { return }
        repeatOneRestartConsumed = false  // a new track re-arms the restart-once gate
        // Track the load position so a recoverable failure rebuilds here (not at 0). A
        // brand-new track loads with seekTo == nil → the snapshot resets to 0.
        lastKnownMusicPosition = seekTo ?? 0
        // Fresh track → fresh recovery budget and a fresh gone check.
        resetRecoveryBudget()
        goneCheckedTrackId = nil
        let track = queue[currentIndex]
        hydrateCurrentTrackCoverIfNeeded()  // radio/shuffle/vibe tracks arrive without album metadata
        let client = apiClient
        // Staleness guard: claim at mint (loadEpoch). The claim is minted before the hop, so a second load intent
        // (user next, recovery rebuild, cross-file seek) cancels the in-flight one instead of racing it.
        // Landings and teardowns bump the epoch (monotonic, never zeroed) so a stale claim can never collide.
        let loadClaim = engine.claimLoad()
        loadStream(claim: loadClaim, client: client, autoplay: autoplay, seekTo: seekTo) { [weak self] token in
            guard let self else { return nil }
            return StreamURL.track(base: self.server, trackId: track.id, token: token)
        }
        refillStationIfAtTail()
    }
}
