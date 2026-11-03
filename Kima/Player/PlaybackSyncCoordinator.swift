import Foundation
import os

private let syncLog = Logger(subsystem: "com.chevron7locked.kima", category: "sync")

/// Owns the server-side playback-state sync loop for music (`@MainActor`; the `KimaAPIClient` actor is awaited).
/// Saves are coalesced over 1 s into one POST and go out in order, so an older queue never lands after a newer one.
/// Hydration (one GET on `start()`) and a 30 s poll apply state only while nothing is loaded; the poll stops on a 401.
/// Applying never calls `syncHook`, and `lastServerSync` follows each save's `updatedAt`, so there is no echo loop.
@MainActor
final class PlaybackSyncCoordinator {

    // MARK: - Dependencies

    private weak var controller: PlaybackController?
    private let client: KimaAPIClient

    // MARK: - Sync state

    /// Timestamp of the most recent state we have synced (saved or received via GET).
    /// Nil until the first successful GET. The timestamp-wins guard is bypassed when nil
    /// (so the very first poll always applies if newer than nothing).
    private var lastServerSync: Date?

    /// Latched to true after a 401 — both poll and save are permanently gated on this flag.
    private var authFailed = false

    // MARK: - Tasks

    /// The 1 s pause before a save; a newer change restarts it.
    private var debounceTask: Task<Void, Never>?
    /// The save being sent, or the last one sent. The next save waits for it.
    private var postTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    /// Save coalescing window and poll interval (tests shorten them).
    var saveDelay: Duration = .seconds(1)
    var pollInterval: Duration = .seconds(30)

    // MARK: - Init / lifecycle

    init(controller: PlaybackController, client: KimaAPIClient) {
        self.controller = controller
        self.client = client
    }

    deinit {
        debounceTask?.cancel()
        postTask?.cancel()
        pollTask?.cancel()
    }

    /// Begin hydration (once) then the 30-second poll loop.
    /// Called by `AppEnvironment` after the controller's `syncHook` is wired so no mutation
    /// events are missed between creation and the first hydration fetch.
    func start() {
        Task { @MainActor [weak self] in
            await self?.hydrate()
            self?.beginPolling()
        }
    }

    /// Permanently stop the poll and any pending save. Call on sign-out.
    func stop() {
        authFailed = true
        debounceTask?.cancel()
        postTask?.cancel()
        pollTask?.cancel()
    }

    // MARK: - Save (1s debounce)

    /// Monotonic save sequence — bumped per schedule; a save whose number is no longer the newest
    /// steps aside for the newer one, which carries fresher state.
    private var saveGeneration = 0

    /// Schedule a debounced save. Restarts the 1-second timer; if no further call arrives within
    /// that window, the save is queued behind any save still being sent. Mirrors the web client's
    /// 1-second coalescing window.
    func scheduleStateSave() {
        guard !authFailed else { return }
        saveGeneration &+= 1
        let generation = saveGeneration
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let delay = self?.saveDelay else { return }
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.queueSave(generation: generation)
        }
    }

    /// Send this save after the one before it has finished, so the server sees them in order.
    private func queueSave(generation: Int) {
        let previous = postTask
        postTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, generation == self.saveGeneration else { return }
            await self.performSave(generation: generation)
        }
    }

    // MARK: - Hydration

    private func hydrate() async {
        do {
            guard let state = try await client.getPlaybackState() else { return }
            await applyServerState(state, isHydration: true)
        } catch {
            // Non-fatal on mount — user can still play normally without prior state.
            syncLog.error("hydrate failed (non-fatal): \(String(describing: error), privacy: .private)")
        }
    }

    // MARK: - Poll

    private func beginPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.pollInterval else { return }
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self, !self.authFailed else { return }
                await self.poll()
            }
        }
    }

    private func poll() async {
        // A loaded queue is never replaced by the server's, so there is nothing to fetch.
        guard controller?.canAdoptServerQueue == true else { return }
        do {
            guard let state = try await client.getPlaybackState() else { return }
            await applyServerState(state, isHydration: false)
        } catch APIError.unauthorized {
            // Permanently stop: an auth failure ends the poll.
            authFailed = true
            pollTask?.cancel()
        } catch {
            // Transient network error — keep polling at next interval.
        }
    }

    // MARK: - Apply server state (timestamp-wins)

    private func applyServerState(_ state: PlaybackStateResponse, isHydration: Bool) async {
        // Only music tracks hydrate; long-form progress is saved separately (saveProgress).
        guard state.playbackType == "track" else { return }

        // Timestamp-wins guard: skip if server state is not newer than our last sync.
        // When lastServerSync is nil (first ever fetch), always apply.
        if let updatedAtStr = state.updatedAt,
           let serverDate = parseISO8601(updatedAtStr) {
            if let last = lastServerSync, serverDate <= last {
                // Our own echo or an older remote write — ignore.
                return
            }
            if isHydration {
                // Record the baseline so the first poll doesn't re-apply the same state.
                lastServerSync = serverDate
            }
        }

        guard let controller else { return }

        // Hydration-only guard: don't overwrite a live session on mount.
        if isHydration && !controller.canAdoptServerQueue {
            return
        }

        guard let serverQueue = state.queue, !serverQueue.isEmpty else { return }

        // QueueTrack → Track via JSON round-trip. Resilient to future Track field additions.
        // Only id / title / duration / artist / album decode; all other Track fields are nil.
        // Runs off @MainActor (detached utility task) — guard let binding keeps controller alive.
        let tracks = await decodeTracks(from: serverQueue)
        guard !tracks.isEmpty else { return }

        let clampedIndex = max(0, min(state.currentIndex, tracks.count - 1))

        // Apply queue / index / shuffle WITHOUT loading the engine or autoplaying (§4.4).
        // hydrateFromServer does NOT call syncHook — no save is triggered by this apply.
        controller.hydrateFromServer(
            queue: tracks,
            currentIndex: clampedIndex,
            isShuffle: state.isShuffle
        )
    }

    // MARK: - Save execution

    private func performSave(generation: Int) async {
        guard !authFailed else { return }
        guard let controller else { return }

        // Only save when there's an active music queue with a current track.
        guard !controller.queue.isEmpty,
              let currentTrack = controller.currentTrack else { return }

        // Cap queue to 2000 entries. Snapshot index + shuffle before
        // yielding to the encode task so we send a consistent state snapshot.
        let cappedQueue     = Array(controller.queue.prefix(2000))
        let snapshotIndex   = controller.currentIndex
        let snapshotShuffle = controller.isShuffle

        // Encode off @MainActor to avoid blocking the render loop (20–60 ms for 2000 tracks).
        let queueTracks  = await encodeQueue(cappedQueue)
        guard !queueTracks.isEmpty else { return }
        // If a newer save was scheduled while we were encoding, let it win — don't land a stale
        // out-of-order write over fresher state.
        guard generation == saveGeneration else { return }
        let clampedIndex = max(0, min(snapshotIndex, queueTracks.count - 1))

        do {
            let response = try await client.savePlaybackState(
                playbackType: "track",
                trackId: currentTrack.id,
                queue: queueTracks,
                currentIndex: clampedIndex,
                isShuffle: snapshotShuffle
            )
            // Advance lastServerSync from the response's updatedAt so the next poll ignores
            // our own echo.
            if let updatedAtStr = response.updatedAt,
               let date = parseISO8601(updatedAtStr) {
                lastServerSync = date
            }
        } catch APIError.unauthorized {
            authFailed = true
            pollTask?.cancel()
        } catch {
            // Transient failure — non-fatal, will retry on the next mutation.
            syncLog.error("save failed (retries on the next change): \(String(describing: error), privacy: .private)")
        }
    }

    // MARK: - Encode / decode helpers

    /// The queue in the server's stored shape (`QueueTrack(_:)`), built off @MainActor on a utility task.
    private func encodeQueue(_ tracks: [Track]) async -> [QueueTrack] {
        await Task.detached(priority: .utility) { tracks.map(QueueTrack.init) }.value
    }

    /// Decode a QueueTrack array to Track via a single JSON round-trip, running off
    /// @MainActor on a utility background task. Fresh encoder/decoder per call.
    /// Tracks produced this way have only id / title / duration / artist / album; all other
    /// Track fields are nil (optional). Sufficient for queue display and stream URL building.
    private func decodeTracks(from queueTracks: [QueueTrack]) async -> [Track] {
        await Task.detached(priority: .utility) {
            let enc = JSONEncoder()
            let dec = JSONDecoder()
            guard let data = try? enc.encode(queueTracks),
                  let tracks = try? dec.decode([Track].self, from: data) else { return [] }
            return tracks
        }.value
    }

    // MARK: - ISO 8601 parsing

    /// Parse Prisma's ISO 8601 timestamps (e.g. "2024-01-15T12:00:00.000Z").
    /// Delegates to the shared cached formatters in `Formatters`.
    private func parseISO8601(_ string: String) -> Date? {
        Formatters.parseISO8601(string)
    }
}
