import Foundation
import Observation

// Refresh: SSE downloadTick drives updates; a 30-second poll is the safety net (startPolling).
// Task lifecycle: pollTask is cancelled in stopPolling(), called from the view's onDisappear.

/// Lightweight Sendable error carrying a display message, so per-list fetch outcomes
/// can be returned as `Result` across the concurrent `async let` boundary.
/// (`Result`'s `Failure` must conform to `Error`; `String` does not.)
private struct DownloadError: Error, Sendable { let message: String }

@MainActor
@Observable
final class ActiveDownloadsViewModel {

    // MARK: - Published state

    var downloads: [DownloadJob] = []
    var failedAlbums: [FailedAlbum] = []
    var isLoading = false
    var error: String?

    /// IDs of jobs whose cancel button was tapped; drives per-row spinner.
    var cancellingIds: Set<String> = []
    /// IDs of failed entries being dismissed.
    var dismissingIds: Set<String> = []

    // MARK: - Internals

    @ObservationIgnored
    private var pollTask: Task<Void, Never>?

    // MARK: - Polling lifecycle

    /// Begin a 30-second reconciliation poll. SSE `downloadTick` already refreshes on every server change, so the
    /// poll is only a safety net for gaps (missed SSE events, foreground resume).
    /// Call from `.task {}` so SwiftUI cancels it on disappear.
    func startPolling(client: KimaAPIClient) {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await self?.fetch(client: client, showSpinner: false)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Load

    /// Initial load (shows the full-screen spinner on first fetch).
    func initialLoad(client: KimaAPIClient) async {
        await fetch(client: client, showSpinner: true)
    }

    private func fetch(client: KimaAPIClient, showSpinner: Bool) async {
        if showSpinner { isLoading = true; error = nil }
        defer { if showSpinner { isLoading = false } }

        // Run both requests concurrently, but reconcile each list independently — a
        // failure in one must NOT discard the other's results.
        async let activeOutcome = loadActive(client: client)
        async let failedOutcome = loadFailed(client: client)
        let active = await activeOutcome
        let failed = await failedOutcome

        var firstError: String?
        switch active {
        case .success(let jobs): downloads = jobs
        case .failure(let e): firstError = e.message
        }
        switch failed {
        case .success(let albums): failedAlbums = albums
        case .failure(let e): if firstError == nil { firstError = e.message }
        }
        if showSpinner, let firstError { error = firstError }
    }

    /// Fetch active downloads, capturing any failure as a message (Sendable `Result`).
    private func loadActive(client: KimaAPIClient) async -> Result<[DownloadJob], DownloadError> {
        do { return .success(try await client.getActiveDownloads()) }
        catch { return .failure(DownloadError(message: error.localizedDescription)) }
    }

    /// Fetch failed-album notifications, capturing any failure as a message.
    private func loadFailed(client: KimaAPIClient) async -> Result<[FailedAlbum], DownloadError> {
        do { return .success(try await client.getFailedDownloads()) }
        catch { return .failure(DownloadError(message: error.localizedDescription)) }
    }

    // MARK: - Cancel actions

    /// DELETE /api/downloads/:id — cancels a single job and removes it from the local list.
    func cancelDownload(id: String, client: KimaAPIClient, toast: ToastCenter) async {
        guard !cancellingIds.contains(id) else { return }
        cancellingIds.insert(id)
        defer { cancellingIds.remove(id) }
        do {
            try await client.deleteDownload(id: id)
            downloads.removeAll { $0.id == id }
        } catch {
            toast.show("couldn't cancel the download", style: .error)
            // Reconcile with server — the job's true state is now uncertain.
            await fetch(client: client, showSpinner: false)
        }
    }

    /// Cancels every active download in parallel.
    func cancelAll(client: KimaAPIClient, toast: ToastCenter) async {
        // Capture the exact set being cancelled up front so it can't drift if the poll
        // loop mutates `downloads` mid-operation.
        let ids = Set(downloads.map { $0.id })
        guard !ids.isEmpty else { return }
        cancellingIds.formUnion(ids)
        defer { cancellingIds.subtract(ids) }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask { try await client.deleteDownload(id: id) }
                }
                try await group.waitForAll()
            }
            // Remove only the jobs we actually cancelled — preserve any that arrived
            // since `ids` was captured.
            downloads.removeAll { ids.contains($0.id) }
        } catch {
            // Partial failure — refresh from server for accuracy.
            await fetch(client: client, showSpinner: false)
            toast.show("couldn't cancel some downloads", style: .error)
        }
    }

    // MARK: - Dismiss failed

    /// DELETE /api/downloads/failed/:id — removes a failed-album notification.
    func dismissFailed(id: String, client: KimaAPIClient, toast: ToastCenter) async {
        guard !dismissingIds.contains(id) else { return }
        dismissingIds.insert(id)
        defer { dismissingIds.remove(id) }
        do {
            try await client.deleteFailedDownload(id: id)
            failedAlbums.removeAll { $0.id == id }
        } catch {
            toast.show("couldn't remove it. try again.", style: .error)
        }
    }
}
