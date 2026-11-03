import Foundation
import UIKit

// MARK: - Play reporting wiring (music only)
// Owns the ListenMeter and feeds it: engine.onTick (1 Hz), seek / gapless advance (breakChain), track change (reset).
// Reset only on a track change; a late duration keeps the reported flag, and resetting double-counts. Scene changes
// can land mid-tick, so flush on background / termination plus a 60 s heartbeat; the server's dedup absorbs overlap.

extension PlaybackController {

    /// Attach the listen meter to this controller. Called by AppEnvironment right
    /// after `apiClient` is assigned; call again to replace the client (login swap).
    func attachPlayReporting(client: KimaAPIClient) {
        playReportClient = client
        startBackgroundPlayObservers()
    }

    /// Music-track seam called from engine.onTick. `trackId` nil (long-form / empty
    /// queue) keeps the meter idle; a late queue track adopts the current duration.
    func observePlayPosition(trackId: String?) {
        guard let trackId, !playbackType.isLongForm else { return }
        if meterTrackId != trackId {
            meterTrackId = trackId
            playMeter.reset(durationSeconds: duration > 0 ? duration : nil)
        }
        if engine.duration > 0 { playMeter.setDuration(engine.duration) }
        reportIfNeeded(meter: playMeter, trackId: trackId)
    }

    /// Flush on a scene transition, engine-side ended, app termination, or the
    /// background heartbeat. Safe to call often: the meter reports at most once
    /// per listen.
    func flushPlayMeter() {
        guard let trackId = meterTrackId, !playbackType.isLongForm else { return }
        reportIfNeeded(meter: playMeter, trackId: trackId)
    }

    private var playMeterTicking: Bool {
        engine.isPlaying && !playbackType.isLongForm && meterTrackId != nil
    }

    private func reportIfNeeded(meter: ListenMeter, trackId: String) {
        guard meter.observe(currentTime) else { return }
        let seconds = meter.secondsListened
        guard let client = playReportClient else { return }
        sendPlayReport(client: client, trackId: trackId, seconds: seconds)
    }

    /// POST the listen without blocking the UI (web `void report(...)`). One that doesn't get through
    /// (offline, a server error) is sent once more after `playReportRetryDelay`; the server treats a
    /// repeat of the same listen within the track's length as a duplicate, so it can't count twice.
    func sendPlayReport(client: KimaAPIClient, trackId: String, seconds: Double) {
        let delay = playReportRetryDelay
        Task {
            if await client.reportPlay(trackId: trackId, secondsListened: seconds) { return }
            try? await Task.sleep(for: delay)
            await client.reportPlay(trackId: trackId, secondsListened: seconds)
        }
    }

    // MARK: Background / heartbeat observers

    private func startBackgroundPlayObservers() {
        if playReportTokens == nil {
            var tokens: [NSObjectProtocol] = []
            let nc = NotificationCenter.default
            tokens.append(nc.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.flushPlayMeter() }
            })
            tokens.append(nc.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.setPlayHeartbeat(active: self?.playMeterTicking ?? false) }
            })
            tokens.append(nc.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.flushPlayMeter()
                    self?.setPlayHeartbeat(active: false)
                }
            })
            tokens.append(nc.addObserver(
                forName: UIApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.flushPlayMeter() }
            })
            playReportTokens = tokens
        }
    }

    private func setPlayHeartbeat(active: Bool) {
        playHeartbeatTask?.cancel()
        playHeartbeatTask = nil
        guard active else { return }
        playHeartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                guard self.playMeterTicking else { return }  // paused/stopped in background → stop beating
                self.flushPlayMeter()
            }
        }
    }
}
