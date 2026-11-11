import AVFoundation
import Foundation
import Observation

/// One shared 30-second clip player for album, artist and browse-playlist screens.
/// It pauses main playback while a clip plays and gives it back only when the clip
/// ends on its own; a manual stop or a screen change does not resume. The one yield rule:
/// main playback going audible — the fetching half included, ADR 0001's `isAudibleNow` —
/// silences the clip here, so no page watches for it (ticket 05).
@MainActor
@Observable
final class ClipPreviewPlayer {

    /// Id of the clip that is playing now, or nil when idle.
    private(set) var previewingId: String?

    @ObservationIgnored private var avPlayer: AVPlayer?
    @ObservationIgnored private var endToken: Any?
    @ObservationIgnored private var failToken: Any?
    @ObservationIgnored private var resolvingId: String?
    @ObservationIgnored private weak var mainPlayer: PlaybackController?
    @ObservationIgnored private var pausedMain = false
    /// Generation of the yield observation; bumping it retires any in-flight change callback.
    @ObservationIgnored private var yieldToken = 0

    /// Tapping the playing clip stops it; tapping another starts it. Re-taps are ignored
    /// while a stream address is still being fetched.
    func toggle(id: String, mainPlayer: PlaybackController, resolveURL: () async -> URL?) async {
        if previewingId == id {
            stop()
            return
        }
        guard resolvingId == nil else { return }
        resolvingId = id
        let url = await resolveURL()
        resolvingId = nil
        guard let url else { return }
        start(id: id, url: url, mainPlayer: mainPlayer)
    }

    func stop() {
        yieldToken += 1   // retire the yield observation with the clip it guarded
        avPlayer?.pause()
        removeTokens()
        avPlayer = nil
        previewingId = nil
        pausedMain = false
    }

    private func start(id: String, url: URL, mainPlayer: PlaybackController) {
        stop()
        self.mainPlayer = mainPlayer
        if mainPlayer.isPlaying {
            mainPlayer.pause()
            pausedMain = true
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        let finish: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.finishNaturally() }
        }
        endToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main, using: finish)
        failToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main, using: finish)
        player.play()
        avPlayer = player
        previewingId = id
        yieldWhenMainGoesAudible(mainPlayer)
    }

    /// The one yield rule for every preview page (ticket 05): main playback becoming audible —
    /// `isAudibleNow`, fetching included — silences this clip before the first byte lands, and
    /// never resumes main: the new thing won. Re-arm loop per CarPlayNowPlaying's playback
    /// tracking; each arm takes a fresh token so a superseded or stopped clip's callback dies at
    /// the guard instead of double-arming.
    private func yieldWhenMainGoesAudible(_ player: PlaybackController) {
        yieldToken += 1
        let token = yieldToken
        withObservationTracking {
            _ = player.isAudibleNow
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.yieldToken == token, let main = self.mainPlayer else { return }
                if main.isAudibleNow {
                    self.stop()
                } else {
                    self.yieldWhenMainGoesAudible(main)
                }
            }
        }
    }

    private func finishNaturally() {
        let resume = pausedMain
        stop()
        if resume { mainPlayer?.resume() }
    }

    private func removeTokens() {
        if let t = endToken { NotificationCenter.default.removeObserver(t) }
        if let t = failToken { NotificationCenter.default.removeObserver(t) }
        endToken = nil
        failToken = nil
    }
}
