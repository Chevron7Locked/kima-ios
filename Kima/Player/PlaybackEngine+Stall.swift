import AVFoundation
import Foundation

// MARK: - Stall watchdog
// AVPlayer can wait forever on a stream that stopped delivering bytes without failing the item. While playback is
// wanted and the engine is loading or buffering, a timer runs; after `stallLimit` with no progress the engine drops
// the item and calls `onStalled`, and the controller rebuilds it at the position like a dropped stream.

extension PlaybackEngine {

    /// The user asked for sound and none is coming yet: a load that hasn't started, or buffering.
    var isWaitingForAudio: Bool {
        wantsPlayback && (status == .loading || status == .buffering)
    }

    /// Arm or disarm the timer to match the current state. Safe to call on every state change.
    func updateStallWatchdog() {
        guard isWaitingForAudio else { cancelStallWatchdog(); return }
        guard stallTask == nil else { return }
        let gen = generation
        let armedAt = currentTime
        let limit = stallLimit
        stallTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: limit)
            guard let self, !Task.isCancelled else { return }
            self.stallTask = nil
            guard self.generation == gen, self.isWaitingForAudio else { return }
            // Time moved during the window (it played between buffers): start a new window.
            guard abs(self.currentTime - armedAt) < 1 else { self.updateStallWatchdog(); return }
            self.giveUpOnStalledItem()
        }
    }

    func cancelStallWatchdog() {
        stallTask?.cancel()
        stallTask = nil
    }

    /// Stop the stuck item and hand it to the controller's recovery. The item stays attached until
    /// the rebuild replaces it; its observers go now so a late failure can't start a second recovery.
    func giveUpOnStalledItem() {
        logger.error("KIMA_AUDIO stall: no audio for \(String(describing: self.stallLimit), privacy: .public) at \(String(format: "%.1f", self.currentTime), privacy: .public)s")
        #if DEBUG
        debugStalled = false
        #endif
        teardownItemObservers()
        generation += 1
        player.pause()
        wasPlayingBeforeFailure = true
        status = .error
        isPlaying = false
        isBuffering = false
        audioError = "the stream timed out"
        onStalled?()
    }

    #if DEBUG
    /// DEBUG: hold the engine in buffering as if the stream stopped sending, so the watchdog and
    /// the recovery can be watched on demand (long-press the ⚡︎ button in the full player).
    func debugSimulateStall() {
        guard status == .playing || status == .buffering else { return }
        logger.error("KIMA_AUDIO DEBUG simulated stall pos=\(String(format: "%.1f", self.currentTime), privacy: .public)s")
        debugStalled = true
        player.pause()
        status = .buffering
        isBuffering = true
        isPlaying = false
        onPlaybackStateChanged?()
        updateStallWatchdog()
    }
    #endif
}
