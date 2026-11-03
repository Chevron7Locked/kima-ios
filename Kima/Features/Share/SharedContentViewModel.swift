import AVFoundation
import Foundation

// MARK: - Load state

enum SharedLoadState {
    case loading
    case loaded(SharedContent)
    /// Token not found or expired / play-limit-exhausted (HTTP 404 / 410).
    case notFound
    case error(String)
}

// MARK: - SharedContentViewModel

/// View model for the public share viewer. Fully self-contained: makes unauthenticated
/// requests directly to /api/share/:token without going through the main KimaAPIClient
/// session. Uses a dedicated no-credential KimaAPIClient so the same infrastructure
/// (ephemeral session, error mapping) applies without attaching a bearer token.
@MainActor
@Observable
final class SharedContentViewModel {

    // MARK: State

    var loadState: SharedLoadState = .loading
    /// Track ID currently playing in the preview player. Nil when nothing is playing.
    var currentTrackId: String? = nil
    /// Whether the preview player is actively playing.
    var isPlaying: Bool = false
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    // MARK: Private

    private let token: String
    private let server: KimaServer
    private let client: KimaAPIClient
    private var player: AVPlayer?

    init(token: String, baseURL: URL) {
        self.token  = token
        self.server = KimaServer(baseURL: baseURL)
        // No credential: the share endpoints are public.
        self.client = KimaAPIClient(server: KimaServer(baseURL: baseURL), credential: nil)
    }

    // MARK: Load

    func load() async {
        loadState = .loading
        do {
            let content = try await client.sharedContent(token: token)
            loadState = .loaded(content)
        } catch let err as APIError {
            switch err {
            case .http(let status, _) where status == 404 || status == 410:
                loadState = .notFound
            default:
                loadState = .error("couldn't load shared content")
            }
        } catch {
            loadState = .error("couldn't connect. check your connection.")
        }
    }

    // MARK: URL builders

    /// Stream URL for a track inside the shared entity — unauthenticated.
    func streamURL(for trackId: String) -> URL? {
        server.api("/share/\(token)/stream/\(trackId)")
    }

    /// Cover art URL via the public share cover-art proxy. Encodes the cover ID as a single
    /// percent-encoded path component (matching JS encodeURIComponent behaviour), then appends
    /// a size query param so the server returns an appropriately-scaled JPEG.
    func coverURL(for coverId: String, size: Int = 256) -> URL? {
        guard !coverId.isEmpty else { return nil }
        let base = server.baseURL
            .appending(path: "api",        directoryHint: .notDirectory)
            .appending(path: "share",      directoryHint: .notDirectory)
            .appending(path: token,        directoryHint: .notDirectory)
            .appending(path: "cover-art",  directoryHint: .notDirectory)
            .appending(component: coverId, directoryHint: .notDirectory)
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [URLQueryItem(name: "size", value: "\(size)")]
        return comps.url
    }

    // MARK: Playback

    /// Play a single track from the shared entity. Creates or replaces the internal AVPlayer.
    func play(trackId: String) {
        guard let url = streamURL(for: trackId) else { return }
        let item = AVPlayerItem(url: url)
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
                await self?.player?.seek(to: .zero)
            }
        }
        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }
        player?.play()
        currentTrackId = trackId
        isPlaying = true
    }

    /// Toggle play/pause for the currently-playing track.
    func togglePlayPause(trackId: String) {
        if currentTrackId == trackId && isPlaying {
            player?.pause()
            isPlaying = false
        } else if currentTrackId == trackId && !isPlaying {
            player?.play()
            isPlaying = true
        } else {
            play(trackId: trackId)
        }
    }

    private func removeEndObserver() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    func stopPlayback() {
        removeEndObserver()
        player?.pause()
        player = nil
        currentTrackId = nil
        isPlaying = false
    }
}
