import Foundation
import MediaPlayer

// MARK: - NowPlayingController remote-command registration
// Handler blocks fire on a system queue and run their work on the main actor through `onMain`, so each one can
// report what actually happened. `controller` is internal so this extension can read it across the file boundary.

extension NowPlayingController {

    // MARK: - Remote Commands (registered once in init)

    func registerRemoteCommands() {
        let rc = MPRemoteCommandCenter.shared()

        // Clear any stale handlers from a previous session so we never double-register.
        rc.playCommand.removeTarget(nil)
        rc.pauseCommand.removeTarget(nil)
        rc.togglePlayPauseCommand.removeTarget(nil)
        rc.nextTrackCommand.removeTarget(nil)
        rc.previousTrackCommand.removeTarget(nil)
        rc.changePlaybackPositionCommand.removeTarget(nil)
        rc.skipForwardCommand.removeTarget(nil)
        rc.skipBackwardCommand.removeTarget(nil)
        rc.changePlaybackRateCommand.removeTarget(nil)

        rc.playCommand.isEnabled              = true
        rc.pauseCommand.isEnabled             = true
        rc.togglePlayPauseCommand.isEnabled   = true
        rc.nextTrackCommand.isEnabled         = true
        rc.previousTrackCommand.isEnabled     = true
        rc.changePlaybackPositionCommand.isEnabled = true
        rc.skipForwardCommand.isEnabled       = true
        rc.skipBackwardCommand.isEnabled      = true
        // Actual enablement is long-form-only — toggled per playback type in refresh(),
        // mirroring the skip-interval / next-prev toggling below it.
        rc.changePlaybackRateCommand.isEnabled = true
        rc.changePlaybackRateCommand.supportedPlaybackRates =
            CarPlayNowPlaying.rates.map { NSNumber(value: $0) }   // [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

        // Intervals are updated in refresh() based on playback type (15 s music / 30 s long-form).
        rc.skipForwardCommand.preferredIntervals  = [15]
        rc.skipBackwardCommand.preferredIntervals = [15]

        // Each handler runs on the main actor and answers truthfully: with nothing loaded it says
        // so (`.noActionableNowPlayingItem`) instead of claiming success.

        rc.playCommand.addTarget { [weak self] _ in
            Self.onMain {
                guard let c = self?.controller, c.isActive else { return .noActionableNowPlayingItem }
                c.resume()
                return .success
            }
        }

        rc.pauseCommand.addTarget { [weak self] _ in
            Self.onMain {
                guard let c = self?.controller, c.isActive else { return .noActionableNowPlayingItem }
                c.pause()
                return .success
            }
        }

        rc.togglePlayPauseCommand.addTarget { [weak self] _ in
            Self.onMain {
                guard let c = self?.controller, c.isActive else { return .noActionableNowPlayingItem }
                c.togglePlayPause()
                return .success
            }
        }

        rc.nextTrackCommand.addTarget { [weak self] _ in
            Self.onMain {
                guard let c = self?.controller, c.isActive else { return .noActionableNowPlayingItem }
                guard c.currentTrack != nil else { return .commandFailed }  // long-form has no music queue
                c.next()
                return .success
            }
        }

        rc.previousTrackCommand.addTarget { [weak self] _ in
            Self.onMain {
                guard let c = self?.controller, c.isActive else { return .noActionableNowPlayingItem }
                guard c.currentTrack != nil else { return .commandFailed }  // long-form has no music queue
                c.previous()
                return .success
            }
        }

        rc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let seekEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = seekEvent.positionTime
            return Self.onMain {
                guard let c = self?.controller, c.isActive else { return .noActionableNowPlayingItem }
                c.seek(to: position)
                return .success
            }
        }

        // Skip intervals are updated in refresh() to 15 s (music) or 30 s (long-form).
        rc.skipForwardCommand.addTarget { [weak self] _ in
            Self.onMain {
                guard let c = self?.controller, c.isActive else { return .noActionableNowPlayingItem }
                c.skip(by: c.playbackType.isLongForm ? 30 : 15)
                return .success
            }
        }

        rc.skipBackwardCommand.addTarget { [weak self] _ in
            Self.onMain {
                guard let c = self?.controller, c.isActive else { return .noActionableNowPlayingItem }
                c.skip(by: c.playbackType.isLongForm ? -30 : -15)
                return .success
            }
        }

        // Long-form only (gated in refresh()) — drives the same setLongFormSpeed path as
        // CarPlay's speed button and the in-app speed picker, so there is one speed mutation
        // site regardless of which surface changed it.
        rc.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let rateEvent = event as? MPChangePlaybackRateCommandEvent else {
                return .commandFailed
            }
            return Self.onMain {
                guard let c = self?.controller, c.isActive else { return .noActionableNowPlayingItem }
                guard c.playbackType.isLongForm else { return .commandFailed }
                // setLongFormSpeed re-pushes now-playing internally (→ nowPlayingHook), so no
                // second hook call here — that would double-rebuild the info dict per rate change.
                c.setLongFormSpeed(Float(rateEvent.playbackRate))
                return .success
            }
        }
    }

    /// Remote-command handlers arrive on a system queue (in practice the main thread). Runs `body`
    /// on the main actor and returns its answer to the system.
    nonisolated static func onMain(
        _ body: @MainActor () -> MPRemoteCommandHandlerStatus
    ) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread { return MainActor.assumeIsolated(body) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }
}
