import Foundation

// MARK: - Navigation, shuffle/repeat toggles, and end/fail handling
//
// Queue-mutation logic (enqueue, shuffle-order build, remove/move/clear) lives in
// PlaybackController+QueueEditing.swift.

extension PlaybackController {

    // MARK: - Previous

    /// If `currentTime > 3 s` restart current; else go to the previous track (shuffle-aware).
    /// At the beginning of a non-repeating queue, restart the first track.
    func previous() {
        guard !queue.isEmpty else { return }
        cancelSkipDebounce()  // a pending skip must not seek the new item
        cancelStationResume()

        // Restart current if more than 3 s in.
        if engine.currentTime > 3 {
            engine.seek(to: 0)
            if !engine.isPlaying { engine.play() }
            nowPlayingHook?()
            return
        }

        let (prevIdx, prevShufflePos) = computePrev()
        if let prevIdx {
            currentIndex = prevIdx
            if let prevShufflePos { shufflePosition = prevShufflePos }
            loadCurrentTrack(autoplay: engine.isPlaying)
            nowPlayingHook?()
            syncHook?()        // currentIndex changed
        } else {
            // At the beginning — restart current.
            engine.seek(to: 0)
            if !engine.isPlaying { engine.play() }
        }
    }

    // MARK: - Next

    /// Advance to the next track. On `repeatMode == .one` the FIRST manual Next restarts the
    /// current track; only a SECOND advances. After the restart-once is
    /// consumed, `repeat-one` behaves like `repeat-all` for skip purposes (the natural-end loop
    /// is handled separately in `handleEnded`).
    func next() {
        guard !queue.isEmpty else { return }
        cancelSkipDebounce()  // a pending skip must not seek the new item
        cancelStationResume()

        // Repeat-one: first manual Next restarts; second advances.
        if repeatMode == .one && !repeatOneRestartConsumed {
            repeatOneRestartConsumed = true
            engine.seek(to: 0)
            if !engine.isPlaying { engine.play() }
            nowPlayingHook?()
            return
        }

        let (nextIdx, nextShufflePos) = computeNextForManual()
        if let nextIdx {
            currentIndex = nextIdx
            if let nextShufflePos { shufflePosition = nextShufflePos }
            loadCurrentTrack(autoplay: true)
            nowPlayingHook?()
            syncHook?()        // currentIndex advanced
        }
        // nil → end of non-repeating queue on manual skip; stay at current track.
    }

    // MARK: - Transport capabilities (for enabling the transport buttons)

    /// Whether a manual `next()` would do anything from the current track, so views can grey out Next
    /// at the end of the queue. Same rules as `next()`: any repeat mode makes the press do something;
    /// with repeat off there must be a track after the current one in play order.
    var canGoNext: Bool {
        guard !queue.isEmpty else { return false }
        if repeatMode == .one && !repeatOneRestartConsumed { return true }
        return peekNext(wraps: repeatMode != .off).queueIndex != nil
    }

    /// Whether a manual `previous()` would do anything from the current track. Views use it to
    /// grey out Previous at the start of the queue. Mirrors `previous()`'s rules: more than 3 s
    /// into a track, Previous restarts it; otherwise there must be a track before the current
    /// one in play order (repeat-all wraps to the last).
    var canGoPrevious: Bool {
        guard !queue.isEmpty else { return false }
        if engine.currentTime > 3 { return true }
        return computePrev().queueIndex != nil
    }

    // MARK: - Shuffle

    /// Fisher-Yates over all queue indices except current, prepend current.
    /// Toggling shuffle off clears the order; back on regenerates.
    func toggleShuffle() {
        guard !queuePlaysInOrder else { return }  // a vibe queue or an in-order station
        isShuffle.toggle()
        if isShuffle, !queue.isEmpty {
            shuffleOrder = buildShuffleOrder(keeping: currentIndex, total: queue.count)
            shufflePosition = 0
        } else {
            shuffleOrder = []
            shufflePosition = 0
        }
        nowPlayingHook?()
        syncHook?()        // isShuffle changed
    }

    // MARK: - Repeat

    func cycleRepeat() {
        repeatMode = repeatMode.next
        repeatOneRestartConsumed = false  // re-arm the restart-once gate
        nowPlayingHook?()
    }

    // MARK: - Queue jump (for QueueSheet)

    /// Jump directly to `queue[index]`, ignoring the 3-second restart rule of `previous()`. With shuffle on, the
    /// shuffle cursor tracks the new index in `shuffleOrder`. Autoplays. Out-of-bounds `index` is ignored.
    func jumpTo(index: Int) {
        guard queue.indices.contains(index) else { return }
        cancelSkipDebounce()
        cancelStationResume()

        currentIndex = index

        // Keep the shuffle cursor consistent so next()/previous() stay coherent after the jump.
        if isShuffle, let shufflePos = shuffleOrder.firstIndex(of: index) {
            shufflePosition = shufflePos
        }

        loadCurrentTrack(autoplay: true)
        nowPlayingHook?()
        syncHook?()        // currentIndex changed
    }

    // MARK: - onEnded handler — TRACK path + long-form branches

    func handleEnded() {
        cancelSkipDebounce()  // a pending skip must not seek the next item
        // Play reporting: flush the finished track's listen before advancing
        // (engine.onEnded flush; the meter auto-resets on the next track's first tick).
        flushPlayMeter()

        // Sleep timer "end of track/episode/chapter": pause instead of advancing.
        // Checked BEFORE repeat-one and long-form auto-advance so neither defeats it.
        if consumeSleepAfterCurrentItem() { return }

        // Long-form types handle their own ended logic.
        if case .audiobook = playbackType {
            handleAudiobookFileEnded()
            return
        }
        if case .podcastEpisode = playbackType {
            handlePodcastEpisodeEnded()
            return
        }

        guard !queue.isEmpty else { return }

        if repeatMode == .one {
            // Natural end with repeat-one: loop without reloading the stream.
            engine.seek(to: 0)
            engine.play()
            nowPlayingHook?()
            return
        }

        let (nextIdx, nextShufflePos) = computeNext()
        if let nextIdx {
            currentIndex = nextIdx
            if let nextShufflePos { shufflePosition = nextShufflePos }
            loadCurrentTrack(autoplay: true)
            nowPlayingHook?()
            syncHook?()        // currentIndex advanced on natural end
        } else {
            // End of queue, repeat off: rest on the last track at 0:00, paused. An item parked
            // at its end ignores play() (AVPlayer), so never leave it there. A station still
            // playing fetches more and resumes at the first new song.
            engine.pause()
            seek(to: 0)
            refillStation(resumeIfEnded: true)
        }
    }

    // MARK: - Music failure policy (the recovery ladder is in +Recovery)

    /// The music error policy: count the error, then either skip to the
    /// next track or stop with an error (the queue and place are kept). Runs only after
    /// `attemptRecovery()` is exhausted or impossible.
    func applyMusicFailurePolicy() {
        consecutiveErrorCount += 1
        if consecutiveErrorCount >= 3 || queue.count <= 1 {
            // Full stop: keep the queue and the place. Tapping play reloads this track
            // (togglePlayPause/resume treat .error as "rebuild here").
            engine.signalExternalError("couldn't play this. tap play to try again.")
            nowPlayingHook?()
        } else {
            // Skip to next track.
            let (nextIdx, nextShufflePos) = computeNextForManual()
            if let nextIdx {
                currentIndex = nextIdx
                if let nextShufflePos { shufflePosition = nextShufflePos }
                loadCurrentTrack(autoplay: true)
            } else {
                engine.signalExternalError("couldn't play this. tap play to try again.")
            }
            nowPlayingHook?()
            syncHook?()        // currentIndex advanced
        }
    }

    // MARK: - Queue advancement helpers

    /// Next index for natural end (`.one` is handled in `handleEnded`). Pure peek with no side
    /// effects — also used by advance prefetch to know which stream to warm while the current
    /// track plays.
    func computeNext() -> (queueIndex: Int?, shufflePos: Int?) {
        peekNext(wraps: repeatMode == .all)
    }

    /// Next index for a manual skip. `repeat-one` is treated as `repeat-all` so the
    /// user can always skip forward regardless of the repeat setting.
    private func computeNextForManual() -> (queueIndex: Int?, shufflePos: Int?) {
        peekNext(wraps: repeatMode != .off)
    }

    /// Shared next-index peek; `wraps` says whether running off the end loops back to the start.
    private func peekNext(wraps: Bool) -> (queueIndex: Int?, shufflePos: Int?) {
        if isShuffle {
            let nextPos = shufflePosition + 1
            if nextPos >= shuffleOrder.count {
                return wraps ? (shuffleOrder[0], 0) : (nil, nil)
            }
            return (shuffleOrder[nextPos], nextPos)
        } else {
            let nextIdx = currentIndex + 1
            if nextIdx >= queue.count {
                return wraps ? (0, nil) : (nil, nil)
            }
            return (nextIdx, nil)
        }
    }

    /// Previous index (shuffle-aware). Returns nil at the beginning of a non-wrapping queue,
    /// which the caller interprets as "restart current".
    private func computePrev() -> (queueIndex: Int?, shufflePos: Int?) {
        if isShuffle {
            let prevPos = shufflePosition - 1
            if prevPos < 0 {
                // Mirror the non-shuffle wrap on repeat-all (on repeat-all).
                let last = shuffleOrder.count - 1
                return repeatMode == .all && last >= 0 ? (shuffleOrder[last], last) : (nil, nil)
            }
            return (shuffleOrder[prevPos], prevPos)
        } else {
            let prevIdx = currentIndex - 1
            if prevIdx < 0 {
                return repeatMode == .all ? (queue.count - 1, nil) : (nil, nil)
            }
            return (prevIdx, nil)
        }
    }
}
