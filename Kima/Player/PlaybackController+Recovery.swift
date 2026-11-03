import AVFoundation
import Foundation
import os

#if DEBUG
// Same subsystem/category as the engine's KIMA_AUDIO probe so `log show` picks it up together.
private let recoveryLog = Logger(subsystem: "com.chevron7locked.kima", category: "engine")
#endif

// MARK: - Mid-stream recovery (music, audiobooks, podcasts)
// When a stream fails or stalls mid-session (often a paused, backgrounded item whose connection dropped), rebuild
// the item from a fresh stream URL at the position it stopped, keeping queue and lock-screen widget. Bounded per
// position: past the budget, music applies the skip / stop policy and long-form stops with its place kept.

extension PlaybackController {

    /// Spend one rebuild from the per-position budget. A position more than 1 s from the current
    /// cycle's (or no cycle yet) starts a fresh cycle. False when the budget is used up.
    func consumeRecoveryBudget(at position: Double) -> Bool {
        if recoveryPosition < 0 || abs(position - recoveryPosition) > 1.0 {
            recoveryPosition = position
            recoveryAttempts = 0
        }
        guard recoveryAttempts < maxRecoveryAttempts else { return false }
        recoveryAttempts += 1
        return true
    }

    /// New content starts with a full budget.
    func resetRecoveryBudget() {
        recoveryAttempts = 0
        recoveryPosition = -1
    }

    /// Id of what is loaded: the track, the audiobook or the episode.
    var nowPlayingItemId: String? {
        switch playbackType {
        case .track:                              return currentTrack?.id
        case .audiobook(let session):             return session.bookId
        case .podcastEpisode(_, let episode, _):  return episode.id
        }
    }

    /// Where a rebuild restarts, in `rebuildCurrentItem` units: seconds into the track or episode,
    /// seconds into the whole audiobook. A load that failed before playing restarts where it was asked to.
    var recoveryPoint: Double {
        let engineTime = engine.pendingSeek ?? engine.currentTime
        switch playbackType {
        case .track:
            return engineTime > 0 ? engineTime : lastKnownMusicPosition
        case .podcastEpisode:
            return engineTime
        case .audiobook(let session):
            return (session.fileByIndex(currentLongFormFileIndex)?.startOffset ?? 0) + engineTime
        }
    }

    // MARK: - Failure entry points

    /// The engine's item failed. A music track that never played gets the gone check first; every
    /// other failure goes to the rebuild ladder.
    func handleFailed() {
        cancelSkipDebounce()  // a pending skip must not seek a torn-down/next item
        // Gone check: a load that never reached .readyToPlay may be a track that no longer exists
        // (album deleted, file gone). Ask the server once per track load before spending the
        // rebuild budget. Mid-play drops (the item had played) go straight to the ladder.
        if case .track = playbackType, !engine.currentLoadReachedReady,
           let id = currentTrack?.id, goneCheckedTrackId != id {
            checkGoneThenRecover()
            return
        }
        recoverOrApplyFailurePolicy()
    }

    /// The watchdog gave up on a stream that stopped sending audio. It is rebuilt like a drop; after
    /// `maxRecoveryAttempts` stalls of one item less than a minute of audio apart, playback stops
    /// with the place kept (web: "playback stalled repeatedly").
    func handleStalled() {
        let item = nowPlayingItemId
        let position = recoveryPoint
        if let anchor = stallAnchor, anchor.item == item, abs(position - anchor.position) <= 60 {
            stallCount += 1
        } else {
            stallCount = 1
        }
        stallAnchor = (item, position)
        guard stallCount <= maxRecoveryAttempts else {
            #if DEBUG
            recoveryLog.error("KIMA_AUDIO stall budget exhausted at \(String(format: "%.1f", position), privacy: .public)s")
            #endif
            stallCount = 0
            engine.signalExternalError("playback keeps stalling. tap play to try again.")
            nowPlayingHook?()
            return
        }
        handleFailed()
    }

    /// The failure ladder: rebuild in place while the per-position budget lasts, then the policy.
    func recoverOrApplyFailurePolicy() {
        if attemptRecovery() { return }
        applyFailurePolicy()
    }

    /// Past the budget: music counts the error and skips or stops; long-form stops with its place kept.
    func applyFailurePolicy() {
        if playbackType.isLongForm {
            engine.signalExternalError("couldn't play this. tap play to try again.")
            nowPlayingHook?()
        } else {
            applyMusicFailurePolicy()
        }
    }

    /// Rebuild the current item at `recoveryPoint` with the play intent it failed with.
    ///
    /// - Returns: `true` when a rebuild was launched (the caller must NOT run the failure policy);
    ///   `false` when nothing is loaded or this position's budget is spent.
    func attemptRecovery() -> Bool {
        guard isActive else { return false }
        let position = recoveryPoint
        guard consumeRecoveryBudget(at: position) else {
            #if DEBUG
            recoveryLog.error("KIMA_AUDIO recovery budget EXHAUSTED at \(String(format: "%.1f", position), privacy: .public)s → failure policy")
            #endif
            return false
        }
        // Play intent at the instant the stream died: playing → resume; paused → stay paused.
        let resumePlaying = engine.wasPlayingBeforeFailure
        #if DEBUG
        recoveryLog.error("KIMA_AUDIO rebuild-at-position \(String(format: "%.1f", position), privacy: .public)s attempt=\(self.recoveryAttempts, privacy: .public) resume=\(resumePlaying, privacy: .public)")
        #endif
        // Preserve the resume point for resume()/togglePlayPause()/AirPod play if the user races
        // the rebuild (the engine is .error until the new item lands).
        if case .track = playbackType { lastKnownMusicPosition = position }
        // The lock screen keeps the item, shown paused, while it rebuilds.
        nowPlayingHook?()
        rebuildCurrentItem(at: position, autoplay: resumePlaying)
        return true
    }

    /// Reload the current item at `position` (`recoveryPoint` units) with a fresh stream ticket: a
    /// clock-valid ticket the server rejects would fail the rebuild too. No ticket or URL ends in
    /// loadStream's terminal error with the queue kept; a repeat failure comes back through
    /// `handleFailed`, and reaching .readyToPlay resets the budget.
    func rebuildCurrentItem(at position: Double, autoplay: Bool) {
        let client = playbackType.isLongForm ? longFormAPIClient : apiClient
        let prepare: @MainActor () async -> Void = { await client?.invalidateStreamTicket() }
        switch playbackType {
        case .track:
            guard queue.indices.contains(currentIndex) else { return }
            let track = queue[currentIndex]
            let claim = engine.claimLoad()  // staleness guard — see loadCurrentTrack
            loadStream(claim: claim, client: client, autoplay: autoplay, seekTo: position > 0 ? position : nil,
                       prepare: prepare) { [weak self] token in
                guard let self else { return nil }
                return StreamURL.track(base: self.server, trackId: track.id, token: token)
            }
        case .audiobook, .podcastEpisode:
            rebuildLongFormStream(at: position, autoplay: autoplay, prepare: prepare)
        }
    }

    // MARK: - Gone tracks (stream 404 — deleted album / file gone)

    /// The stream failed before it ever played: ask the server whether the track still exists
    /// (`KimaAPIClient.streamStatus`). AVPlayerItem's error carries no documented HTTP status, so
    /// the server's own answer is the signal. 404 → `skipGoneTrack()` (no rebuilds, no strike);
    /// anything else, or no answer → the unchanged ladder. Asked once per track load.
    func checkGoneThenRecover() {
        guard let id = currentTrack?.id else { return }
        goneCheckedTrackId = id
        let client = apiClient
        // Observe (don't mint) the play-intent epoch: a newer intent — user next, a new queue, a
        // tap on play — bumps it, and this answer is dropped as stale.
        let epoch = engine.loadEpoch
        Task { @MainActor [weak self] in
            let status = await client?.streamStatus(trackId: id)
            guard let self, self.engine.isCurrentLoad(epoch), self.currentTrack?.id == id else { return }
            #if DEBUG
            recoveryLog.error("KIMA_AUDIO gone-check track=\(id, privacy: .public) status=\(status.map { "\($0)" } ?? "nil", privacy: .public)")
            #endif
            if status == 404 {
                self.skipGoneTrack()
            } else {
                self.recoverOrApplyFailurePolicy()
            }
        }
    }

    /// The current track is gone server-side. Drop it from the queue and play the next one — no
    /// rebuilds, and no strike toward the 3-in-a-row full stop (that rule is for real outages; a
    /// shuffle through deleted albums must not end the session).
    func skipGoneTrack() {
        guard queue.indices.contains(currentIndex) else { return }
        let gone = currentIndex
        #if DEBUG
        recoveryLog.error("KIMA_AUDIO gone-skip track=\(self.queue[gone].id, privacy: .public) remaining=\(self.queue.count - 1, privacy: .public)")
        #endif
        queue.remove(at: gone)
        playerNotice = "skipped a track that's no longer on your server"
        guard !queue.isEmpty else {
            // Every queued track was gone — nothing left to play.
            currentIndex = 0
            shuffleOrder = []
            shufflePosition = 0
            engine.clear()
            nowPlayingHook?()
            syncHook?()
            return
        }

        let landing: Int
        var advance = true
        if isShuffle, let pos = shuffleOrder.firstIndex(of: gone) {
            // Drop the dead slot and renumber the queue indices that sat after it.
            shuffleOrder.remove(at: pos)
            shuffleOrder = shuffleOrder.map { $0 > gone ? $0 - 1 : $0 }
            if pos < shuffleOrder.count {
                shufflePosition = pos
            } else if repeatMode != .off {
                shufflePosition = 0
            } else {
                shufflePosition = shuffleOrder.count - 1
                advance = false
            }
            landing = shuffleOrder[shufflePosition]
        } else {
            // Linear: the following track slid into the dead slot.
            if gone < queue.count {
                landing = gone
            } else if repeatMode != .off {
                landing = 0
            } else {
                landing = queue.count - 1
                advance = false
            }
            if isShuffle {   // order didn't hold the dead index — rebuild it around the landing
                shuffleOrder = buildShuffleOrder(keeping: landing, total: queue.count)
                shufflePosition = 0
            }
        }

        currentIndex = landing
        if advance {
            loadCurrentTrack(autoplay: true)
        } else {
            // The gone track was last and repeat is off: rest on the last real track, unloaded
            // (tapping play reloads it), instead of clearing the queue.
            engine.clear()
        }
        nowPlayingHook?()
        syncHook?()
    }

    #if DEBUG
    /// DEBUG: fire a synthetic stream-drop on the engine so `attemptRecovery()` above runs on
    /// demand (wired to the ⚡︎ button in FullPlayerView). Pause a track first, tap it, and watch the
    /// widget survive + resume at position — the deterministic test for the crown-jewel recovery.
    func debugSimulateStreamDrop() { engine.debugSimulateStreamDrop() }

    /// DEBUG: hold the playing stream in buffering so the stall watchdog fires after `stallLimit`
    /// (long-press the ⚡︎ button). Playback should come back at the same spot.
    func debugSimulateStall() { engine.debugSimulateStall() }

    /// DEBUG: an unplayable queue entry — the server has no track with this id, so its stream
    /// (and detail) answer 404. Used by the skip-missing / skip-gone repro hooks.
    static func debugMissingTrack(id: String, title: String) -> Track {
        Track(id: id, title: title, duration: 0)
    }

    /// DEBUG repro for the "unknown artist after auto-skip" bug (`-kima-open skip-missing`). Round 1 plays a bare
    /// track so its detail fill runs; round 2 queues an unplayable id before a fresh bare copy, so the stream 404s
    /// and the skip policy runs. `syncHook` is cut so the bogus id never reaches the server-saved queue.
    func debugPlayMissingThenReal(_ real: Track) async {
        syncHook = nil
        play(tracks: [real], startAt: 0, shuffle: false)
        try? await Task.sleep(for: .seconds(5))           // let round 1's detail fill land
        let missing = Self.debugMissingTrack(id: "kima-debug-missing-track", title: "missing track")
        play(tracks: [missing, real], startAt: 0, shuffle: false)
    }

    /// DEBUG repro for gone-track skipping (`-kima-open skip-gone`, PlayerArtistHydrationUITests).
    /// Three unplayable ids in front of a real track: each must be dropped with a notice and no
    /// rebuilds or strikes, and the real track must play with the queue still alive. `syncHook`
    /// is cut so the bogus ids never land in the account's server-saved queue.
    func debugPlayThreeMissingThenReal(_ real: Track) {
        syncHook = nil
        let missing = (1...3).map {
            Self.debugMissingTrack(id: "kima-debug-missing-track-\($0)", title: "missing track \($0)")
        }
        play(tracks: missing + [real], startAt: 0, shuffle: false)
    }
    #endif
}
