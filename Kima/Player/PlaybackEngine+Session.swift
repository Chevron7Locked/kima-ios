import AVFoundation
import Foundation

// MARK: - AVAudioSession + interruption + route-change

extension PlaybackEngine {

    // MARK: - Audio session

    /// Claim the `.playback` category with the given mode and activate the session. `.spokenAudio` (audiobooks,
    /// podcasts) gives spoken-content ducking. Called on every `load()` since an interruption may have handed the
    /// category to another app. Background audio depends on this, so a failure is surfaced as a user-visible
    /// error rather than silent dead audio. Returns false when iOS refused the session.
    @discardableResult
    func claimAudioSession(mode: AVAudioSession.Mode? = nil) -> Bool {
        let resolved = mode ?? sessionMode
        sessionMode = resolved
        do {
            try activateSession(resolved)
            return true
        } catch {
            logger.error("AVAudioSession.setCategory/.setActive failed: \(error)")
            status = .error
            audioError = "audio is unavailable. tap play to try again."
            return false
        }
    }

    // MARK: - AVAudioSession interruption + route-change observers

    /// Register for the two session notifications that govern how native audio behaves
    /// when the OS interrupts or re-routes audio. Called once from `init`. The handlers
    /// hop to `@MainActor` via `Task` before touching actor-isolated state, matching the
    /// pattern used throughout this class for KVO and notification callbacks.
    func registerSessionObservers() {
        let nc = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        interruptionToken = nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleInterruption(notification: notification)
            }
        }

        routeChangeToken = nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleRouteChange(notification: notification)
            }
        }
    }

    /// Handle `AVAudioSession.interruptionNotification`.
    private func handleInterruption(notification: Notification) {
        guard
            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type    = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }
        let optionsRaw = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
        handleInterruption(type, shouldResume: AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume))
    }

    /// `.began`: the OS pauses the player; the user's intent (`wantsPlayback`) is left as it was.
    /// `.ended`: if the user still wants playback of a loaded item, resume when iOS allows it
    /// (re-claiming the session), else show tap-to-resume
    /// (`.blocked`). Something the user paused stays paused.
    func handleInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool) {
        switch type {
        case .began:
            // Push lock-screen update immediately; a second push arrives via KVO when
            // timeControlStatus settles.
            onPlaybackStateChanged?()

        case .ended:
            guard wantsPlayback, [.playing, .paused, .buffering].contains(status) else { return }
            if shouldResume {
                // KVO fires when playing starts and pushes the lock screen. A refused session
                // has already shown its error.
                if claimAudioSession() { player.play() }
            } else {
                status    = .blocked
                isPlaying = false
                onPlaybackStateChanged?()
            }

        @unknown default:
            break
        }
    }

    /// Handle `AVAudioSession.routeChangeNotification`. `.oldDeviceUnavailable` (headphones unplugged, Bluetooth
    /// gone): iOS does not pause by itself, so we pause explicitly. `.newDeviceAvailable`: nothing to do, the
    /// player routes there automatically and the category is already claimed.
    private func handleRouteChange(notification: Notification) {
        guard
            let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason    = AVAudioSession.RouteChangeReason(rawValue: reasonRaw)
        else { return }

        if reason == .oldDeviceUnavailable {
            pause()
            // onPlaybackStateChanged fires via applyTimeControlStatus when the KVO settles.
            // Call it explicitly here as a safety net in case KVO races ahead of us.
            onPlaybackStateChanged?()
        }
        // .newDeviceAvailable, .categoryChange, etc. — no action needed.
    }
}
