import AVFoundation
import Foundation
import os

// MARK: - KVO / notification observer setup and teardown

extension PlaybackEngine {

    // MARK: - Periodic time observer (1 Hz)

    func setupPeriodicTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        periodicTimeToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            // The block runs on DispatchQueue.main but is not statically @MainActor in
            // Swift 6 strict concurrency — hop explicitly to access isolated stored properties.
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.status == .playing || self.status == .buffering else { return }
                self.currentTime = time.seconds
                // Fires every second; NowPlayingController.refresh throttles lock-screen position
                // pushes to once per 5 s.
                self.onTick?()
            }
        }
    }

    // MARK: - timeControlStatus KVO

    func setupTimeControlObservation() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyTimeControlStatus(player.timeControlStatus)
            }
        }
    }

    func applyTimeControlStatus(_ tcs: AVPlayer.TimeControlStatus) {
        #if DEBUG
        if debugStalled { return }   // a simulated stall holds the engine in buffering
        #endif
        let prevIsPlaying = isPlaying
        switch tcs {
        case .playing:
            let wasNotPlaying = status != .playing
            status = .playing
            isPlaying = true
            isBuffering = false
            if wasNotPlaying { onPlaying?() }

        case .waitingToPlayAtSpecifiedRate:
            // Avoid overwriting .loading — let item-status KVO advance us to .buffering
            // only once we have a confirmed item in flight.
            if status != .idle && status != .loading {
                status = .buffering
            }
            isPlaying = false
            isBuffering = true

        case .paused:
            isPlaying = false
            isBuffering = false
            // Don't overwrite terminal/load states or the `.blocked` state — the
            // interruption handler owns those transitions; KVO only covers normal play/pause.
            if status == .playing || status == .buffering {
                status = .paused
            }

        @unknown default:
            break
        }
        // Notify whenever the play/pause state actually flips so the lock screen
        // reflects the change immediately (both directions — entering and leaving playing).
        if isPlaying != prevIsPlaying {
            onPlaybackStateChanged?()
        }
        updateStallWatchdog()
    }

    // MARK: - Item observers (AVPlayerItem.status + duration + ended)

    func setupItemObservers(item: AVPlayerItem, generation myGen: Int) {
        // AVPlayerItem.status → readyToPlay (apply pending seek + play) or failed (error ladder)
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] obs, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == myGen else { return }
                self.handleItemStatus(obs.status, item: obs, generation: myGen)
            }
        }

        // Duration — resolves after the item's media characteristics load
        durationObservation = item.observe(\.duration, options: [.new]) { [weak self] obs, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == myGen else { return }
                let d = obs.duration
                if d.isNumeric && d.seconds > 0 { self.duration = d.seconds }
            }
        }

        // AVPlayerItemDidPlayToEndTime → controller drives queue advance
        endedToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == myGen else { return }
                self.onEnded?()
            }
        }
    }

    func handleItemStatus(
        _ itemStatus: AVPlayerItem.Status,
        item: AVPlayerItem,
        generation myGen: Int
    ) {
        defer { updateStallWatchdog() }
        // Drop duplicate deliveries of the same status within one load generation
        // (see `lastDeliveredStatus`); every real transition still passes through.
        if itemStatus == lastDeliveredStatus { return }
        lastDeliveredStatus = itemStatus
        switch itemStatus {
        case .readyToPlay:
            #if DEBUG
            // Gap probe: the audible stops-between-songs window, stamped at load().
            // `prefetch=1` marks a warm advance (warmed asset reused) so measured cold vs
            // warm gaps can be compared in the same `log show` capture.
            let gapMs = Int(Date.now.timeIntervalSince(loadStartedAt) * 1000)
            logger.info("KIMA_AUDIO ready gen=\(myGen, privacy: .public) gap_ms=\(gapMs, privacy: .public) prefetch=\(self.loadUsedPrefetchedURL ? 1 : 0, privacy: .public)")
            #endif
            // A successful ready (even one that lands paused) means any in-flight recovery
            // re-buffered — reset the controller's bounded-retry budget.
            currentLoadReachedReady = true
            onReady?()
            // If there's a pending seek (resume position), apply it BEFORE play so the
            // position indicator never flashes to 0. Play follows the user's intent as it is now,
            // so a pause tapped during the load holds.
            // `pendingSeek` stays set until the seek lands, so a failure in between still resumes there.
            if let target = pendingSeek {
                let t = CMTime(seconds: target, preferredTimescale: 1000)
                player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                    Task { @MainActor [weak self] in
                        self?.finishResumeSeek(finished: finished, target: target, generation: myGen)
                    }
                }
            } else {
                if wantsPlayback { player.play() }
                else             { status = .paused }
            }

        case .failed:
            #if DEBUG
            // Failure probe (unified logging, readable with `log show` on subsystem
            // com.chevron7locked.kima). The NSURLError code, often nested in the underlying error,
            // tells a recoverable connection drop (-1005, -1001) from auth/media causes.
            let e = item.error as NSError?
            let underlying = (e?.userInfo[NSUnderlyingErrorKey] as? NSError).map { "\($0.domain):\($0.code)" } ?? "-"
            let pos = String(format: "%.1f", currentTime)
            let dom = e?.domain ?? "nil"
            let code = e?.code ?? 0
            let desc = e?.localizedDescription ?? "?"
            logger.error("KIMA_AUDIO item .failed pos=\(pos, privacy: .public)s domain=\(dom, privacy: .public) code=\(code, privacy: .public) underlying=\(underlying, privacy: .public) desc=\(desc, privacy: .public)")
            #endif
            // The controller's recovery restores this intent (playing → resume; paused → stay
            // paused) after the in-place rebuild, including a first load that never played.
            wasPlayingBeforeFailure = wantsPlayback
            status = .error
            isPlaying = false
            audioError = Self.humanize(item.error)
            // Hand the raw error to the controller: it rebuilds the item in place at the saved
            // position within the retry budget, then applies the failure policy (a music track
            // that never played is first checked for being gone from the server).
            onFailed?(item.error)

        case .unknown:
            break
        @unknown default:
            break
        }
    }

    /// Human-facing player copy (lowercase ruling; the raw AVFoundation
    /// string, e.g. "The operation couldn’t be completed (NSURLErrorDomain
    /// error -1005.)", goes to the logger, never to Text).
    static func humanize(_ nsError: Error?) -> String {
        let log = Logger(subsystem: "com.chevron7locked.kima", category: "engine")
        guard let nsError = nsError as? NSError,
              nsError.domain == NSURLErrorDomain else {
            log.error("playback failed (non-URL domain): \(nsError?.localizedDescription ?? "nil", privacy: .public)")
            return "playback failed — tap to retry"
        }
        let message: String
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            message = "you appear to be offline"
        case NSURLErrorTimedOut:
            message = "the stream timed out"
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorSecureConnectionFailed:
            message = "can't reach your server"
        case NSURLErrorCancelled:
            message = "playback was interrupted"
        default:
            message = "playback failed — tap to retry"
        }
        log.error("playback failed: \(nsError.domain, privacy: .public) \(nsError.code) \(nsError.localizedDescription, privacy: .public)")
        return message
    }

    /// Completion of the resume seek applied at `.readyToPlay`. A completion for an older item is
    /// dropped. A cancelled seek (a user seek replaced it) still starts playback when the user wants
    /// it, or the item would sit paused at the new spot.
    func finishResumeSeek(finished: Bool, target: Double, generation myGen: Int) {
        guard generation == myGen else { return }
        pendingSeek = nil
        if wantsPlayback {
            player.play()
        } else {
            status = .paused
            if finished { currentTime = target }
        }
        updateStallWatchdog()
    }

    #if DEBUG
    /// DEBUG-only: synthesize a hard `.failed` on the current item, mirroring the `.failed`
    /// KVO path, so the recovery can be exercised ON DEMAND (via the ⚡︎ button in FullPlayerView)
    /// instead of waiting on a flaky real network/Tailscale drop. Fires the KIMA_AUDIO probe too.
    func debugSimulateStreamDrop() {
        let synthetic = NSError(domain: NSURLErrorDomain, code: -1005,
                                userInfo: [NSLocalizedDescriptionKey: "DEBUG simulated stream drop (networkConnectionLost)"])
        let pos = String(format: "%.1f", currentTime)
        logger.error("KIMA_AUDIO DEBUG simulated .failed pos=\(pos, privacy: .public)s code=-1005")
        wasPlayingBeforeFailure = wantsPlayback
        status = .error
        isPlaying = false
        audioError = synthetic.localizedDescription
        onFailed?(synthetic)
    }
    #endif

    // MARK: - Observer teardown (called before item replacement and from deinit)

    func teardownItemObservers() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        durationObservation?.invalidate()
        durationObservation = nil
        if let token = endedToken {
            NotificationCenter.default.removeObserver(token)
            endedToken = nil
        }
    }
}
