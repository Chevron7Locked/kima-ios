import Foundation
import Observation

// MARK: - DiscoverViewModel
// Live `discover:*` events reload the screen while a build runs (DiscoverView). Events sent while the
// live connection is down are lost, so a slow batch-status poll backs them up; after 5 minutes it
// stops watching, refetches, and says the build is still running.

@MainActor
@Observable
final class DiscoverViewModel {

    // MARK: - Observable state

    var playlistPhase: LoadPhase<DiscoverPlaylist> = .loading
    var batchStatus: DiscoverBatchStatus?

    /// True while a generation batch is in flight (pending or active on server).
    var isGenerating: Bool = false

    /// True while the retry-unavailable request is in flight.
    var isRetrying: Bool = false

    /// Set when the app stopped watching a build that was still running; the view says so once
    /// and resets it.
    var stoppedWatchingBuild = false

    // MARK: - Private

    private var pollTask: Task<Void, Never>?
    private var pollStart: Date?
    private let pollInterval: Duration
    private let pollTimeout: TimeInterval

    init(pollInterval: Duration = .seconds(20), pollTimeout: TimeInterval = 300) {
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
    }

    // MARK: - Computed

    var playlist: DiscoverPlaylist? {
        if case .loaded(let p) = playlistPhase { return p }
        return nil
    }

    /// Human-readable generation progress label.
    var progressLabel: String {
        guard isGenerating else { return "" }
        guard let status = batchStatus?.status else { return "working…" }
        switch status {
        case "scanning":    return "finding artists…"
        case "downloading":
            let done  = batchStatus?.completed ?? 0
            let total = batchStatus?.total ?? 0
            return total > 0 ? "downloading (\(done) / \(total))…" : "downloading albums…"
        default:            return "working…"
        }
    }

    // MARK: - Load

    /// Fetch the current playlist and batch status concurrently on first appear / refresh.
    func load(using client: KimaAPIClient) async {
        if case .loaded = playlistPhase {} else { playlistPhase = .loading }
        async let playlistFetch: Void = fetchPlaylist(client)
        async let batchFetch: Void   = syncBatchStatus(client, endsWhenIdle: true)
        _ = await (playlistFetch, batchFetch)
    }

    // MARK: - Generate

    /// Triggers generation. Returns `false` when the request failed so the caller can
    /// toast the error (the VM holds no ToastCenter — the View surfaces errors, mirroring
    /// `retryUnavailable`).
    @discardableResult
    func generate(using client: KimaAPIClient) async -> Bool {
        guard !isGenerating else { return false }
        isGenerating = true
        do {
            try await client.generateDiscoverWeekly()
            await syncBatchStatus(client)
            startPolling(client)
            return true
        } catch {
            isGenerating = false
            return false
        }
    }

    // MARK: - Cancel

    /// Cancels the active batch. Only clears local generating state AFTER the server
    /// confirms the cancel; on failure stays in the generating state and returns `false`
    /// so the caller can toast the error.
    @discardableResult
    func cancelGeneration(using client: KimaAPIClient) async -> Bool {
        do {
            try await client.cancelDiscoverBatch()
        } catch {
            return false   // keep showing generating; caller toasts the failure
        }
        stopPolling()
        batchStatus = DiscoverBatchStatus(
            active: false, status: nil, batchId: nil,
            progress: nil, completed: nil, failed: nil, total: nil
        )
        isGenerating = false
        return true
    }

    // MARK: - Like / Unlike (optimistic, per-album)

    func toggleLike(track: DiscoverTrack, using client: KimaAPIClient) async {
        guard case .loaded(var p) = playlistPhase else { return }

        // Optimistic update — flip all tracks sharing the same albumId
        let newState = !track.isLiked
        applyLikedState(albumId: track.albumId, liked: newState, in: &p)
        playlistPhase = .loaded(p)

        do {
            if newState {
                try await client.likeDiscoverAlbum(albumId: track.albumId)
            } else {
                try await client.unlikeDiscoverAlbum(albumId: track.albumId)
            }
        } catch {
            // Revert on error
            guard case .loaded(var current) = playlistPhase else { return }
            applyLikedState(albumId: track.albumId, liked: !newState, in: &current)
            playlistPhase = .loaded(current)
        }
    }

    // MARK: - Retry unavailable

    /// Outcome of a retry-unavailable request. Lets the caller distinguish a real failure
    /// (toast an error) from a no-op (optional info message) and a success.
    enum RetryOutcome {
        case started(String)    // albums queued — success message
        case noChange(String?)  // nothing to retry — optional info message
        case failed             // request error — caller toasts "retry failed"
    }

    func retryUnavailable(using client: KimaAPIClient) async -> RetryOutcome {
        guard !isRetrying else { return .noChange(nil) }
        isRetrying = true
        defer { isRetrying = false }
        do {
            let (queued, message) = try await client.retryUnavailableAlbums()
            if queued > 0 {
                await syncBatchStatus(client)
                startPolling(client)
                return .started("retrying \(queued) album\(queued == 1 ? "" : "s")")
            }
            return .noChange(message.isEmpty ? nil : message)
        } catch {
            return .failed
        }
    }

    // MARK: - Private helpers

    private func fetchPlaylist(_ client: KimaAPIClient) async {
        do {
            playlistPhase = .loaded(try await client.getCurrentDiscoverWeekly())
        } catch {
            if Task.isCancelled { return }
            if case .loaded = playlistPhase { return }
            playlistPhase = .failed("couldn't load discover weekly.")
        }
    }

    /// `endsWhenIdle`: a reload (first load, pull, a live event) that finds no batch running ends
    /// the "building" state at once. Not after starting a build, which may not show as running yet.
    private func syncBatchStatus(_ client: KimaAPIClient, endsWhenIdle: Bool = false) async {
        do {
            let status = try await client.getDiscoverBatchStatus()
            batchStatus = status
            if status.active {
                isGenerating = true
                if pollTask == nil { startPolling(client) }
            } else if endsWhenIdle, isGenerating {
                stopPolling()
                isGenerating = false
            }
        } catch { /* non-fatal */ }
    }

    private func startPolling(_ client: KimaAPIClient) {
        stopPolling()
        pollStart = Date()
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                if await self.tick(client) { return }
            }
        }
    }

    /// One poll. True when polling is over. Ends with `endPolling`, not `stopPolling`: cancelling
    /// its own task would cancel the playlist refetch that follows.
    private func tick(_ client: KimaAPIClient) async -> Bool {
        if let start = pollStart, Date().timeIntervalSince(start) > pollTimeout {
            endPolling()
            isGenerating = false
            stoppedWatchingBuild = true
            await fetchPlaylist(client)
            return true
        }
        do {
            let status = try await client.getDiscoverBatchStatus()
            batchStatus = status
            if !status.active {
                endPolling()
                isGenerating = false
                await fetchPlaylist(client)
                return true
            }
        } catch { /* transient; keep polling */ }
        return false
    }

    /// Lets go of the running poll without cancelling it.
    private func endPolling() {
        pollTask = nil
        pollStart = nil
    }

    /// Cancels the batch-status poll loop. Internal so the View can call it from
    /// `.onDisappear` as belt-and-suspenders to the `.task {}` auto-cancellation.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        pollStart = nil
    }

    private func applyLikedState(albumId: String, liked: Bool, in playlist: inout DiscoverPlaylist) {
        for i in playlist.tracks.indices where playlist.tracks[i].albumId == albumId {
            playlist.tracks[i].isLiked = liked
        }
    }
}
