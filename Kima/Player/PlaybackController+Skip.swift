import Foundation

extension PlaybackController {

    // MARK: - Skip ±N with 200ms debounce

    /// Accumulate skip taps and fire one real seek 200ms after the last tap.
    /// The `displayTime` is updated immediately so the UI shows progressive feedback
    /// (30 / 60 / 90 s etc.) without waiting for the seek to complete. Default ±30 s.
    func skip(by seconds: Double) {
        // use controller's currentTime / duration (book-absolute for long-form).
        if skipTask == nil {
            skipBase = currentTime
            skipAccumulator = 0
        }
        skipAccumulator += seconds

        // Instant UI update — clamped to [0, duration].
        let dur = duration
        let target = max(0, min(skipBase + skipAccumulator, dur > 0 ? dur : .infinity))
        displayTime = target

        skipTask?.cancel()
        skipTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard !Task.isCancelled else { return }
            let dur2 = self.duration
            let finalTarget = max(0, min(self.skipBase + self.skipAccumulator,
                                         dur2 > 0 ? dur2 : .infinity))
            // performSeekInternal handles cross-file seeks for audiobooks.
            self.performSeekInternal(to: finalTarget)
            self.skipTask = nil
            self.nowPlayingHook?()
        }
    }

    /// Cancel any in-flight skip debounce and sync `displayTime` back to the engine position.
    /// Internal so PlaybackController+Queue.swift can call it from next/previous/etc.
    func cancelSkipDebounce() {
        skipTask?.cancel()
        skipTask = nil
        displayTime = currentTime  // book-absolute for long-form, raw for music
    }
}
