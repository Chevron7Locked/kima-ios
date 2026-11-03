import AVFoundation
import Foundation
import Observation

/// One shared 30-second clip player for album, artist and browse-playlist screens.
/// It pauses the main player while a clip plays and gives it back only when the clip
/// ends on its own; a manual stop, a screen change, or the main player starting does not resume.
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
        avPlayer?.pause()
        removeTokens()
        avPlayer = nil
        previewingId = nil
        pausedMain = false
    }

    private func start(id: String, url: URL, mainPlayer: PlaybackController) {
        stop()
        if mainPlayer.isPlaying {
            mainPlayer.pause()
            pausedMain = true
            self.mainPlayer = mainPlayer
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
