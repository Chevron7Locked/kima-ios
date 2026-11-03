import AVFoundation
import Foundation

extension PlaybackController {

    // MARK: - Transport

    func togglePlayPause() {
        cancelStationResume()
        // While loading or buffering toward playback the button means "stop", like while playing.
        if engine.isPlaying || engine.isWaitingForAudio {
            // Snapshot position so a background stream-drop can rebuild exactly here (a load in
            // flight has no position yet; its resume seek still lands).
            if !playbackType.isLongForm, engineStatus != .loading { lastKnownMusicPosition = engine.currentTime }
            engine.pause()
        } else if engineStatus == .idle || engineStatus == .error {
            reloadCurrentItemAtPosition()
        } else {
            engine.play()
        }
        nowPlayingHook?()
    }

    /// Tapping play when the engine is idle/errored — an unloaded hydrated session, OR the item
    /// detached after a stream drop / an exhausted recovery — must rebuild the current item AT its
    /// last-known position, never restart from 0 (§3). Long-form runs with an EMPTY `queue`, so it
    /// is not gated on `!queue.isEmpty` — it routes through its own rebuild instead.
    private func reloadCurrentItemAtPosition() {
        if playbackType.isLongForm {
            rebuildLongFormStream(at: max(0, lastSavedProgressTime))
        } else if !queue.isEmpty {
            loadCurrentTrack(autoplay: true,
                             seekTo: lastKnownMusicPosition > 0 ? lastKnownMusicPosition : nil)
        } else {
            engine.play()   // nothing loaded and nothing to load → inert
        }
    }

    func pause() {
        cancelStationResume()
        // Snapshot the music position so a resume after a background stream-drop rebuilds
        // exactly here (long-form persists via saveProgress on the same pause).
        if !playbackType.isLongForm { lastKnownMusicPosition = engine.currentTime }
        engine.pause()
        nowPlayingHook?()
    }

    func resume() {
        cancelStationResume()
        if engineStatus == .idle || engineStatus == .error {
            reloadCurrentItemAtPosition()
        } else {
            engine.play()
        }
        nowPlayingHook?()
    }

    func seek(to seconds: Double) {
        cancelSkipDebounce()  // the explicit seek wins over a pending skip
        cancelStationResume()
        performSeekInternal(to: seconds)
        displayTime = seconds; if !playbackType.isLongForm { lastKnownMusicPosition = seconds }
        nowPlayingHook?()
    }
}
