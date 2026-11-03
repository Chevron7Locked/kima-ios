import Foundation

// MARK: - ImportFlowState

enum ImportFlowState {
    case idle
    case previewing                 // POST /preview/start done; polling GET /preview/:jobId
    case previewReady               // preview complete; waiting for user confirmation
    case confirming                 // POST /import (or /import/quick) in-flight
    case done(jobId: String)        // import job started; user directed to Activity
    case error(String)              // user-visible error message
}

// MARK: - ImportViewModel

@Observable
@MainActor
final class ImportViewModel {

    // MARK: - State observed by the view

    var urlText = ""
    var playlistName = ""           // editable; pre-filled from preview.playlist.name
    var state: ImportFlowState = .idle
    var previewResult: ImportPreview?

    // MARK: - Internal (not observed)

    @ObservationIgnored private var previewJobId: String?
    /// The in-flight preview (start + poll) task, so it can be cancelled when the sheet is dismissed.
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    // MARK: - Derived

    var isBusy: Bool {
        switch state {
        case .previewing, .confirming: return true
        default:                        return false
        }
    }

    var canStartPreview: Bool {
        guard case .idle = state else { return false }
        return !urlText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var canConfirm: Bool {
        guard case .previewReady = state else { return false }
        return !playlistName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isDone: Bool {
        if case .done = state { return true }
        return false
    }

    // MARK: - Actions

    /// POST /preview/start, then poll GET /preview/:jobId until the result is ready.
    /// Runs in a stored task so `stop()` (called from the view's onDisappear) cancels the poll
    /// instead of leaving it running for ~90s against a dismissed sheet.
    func startPreview(using client: KimaAPIClient) {
        let url = urlText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }

        state = .previewing
        previewJobId = nil
        previewResult = nil

        previewTask?.cancel()
        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                let jobId = try await client.startPreviewJob(url: url)
                self.previewJobId = jobId
                try await self.pollPreview(jobId: jobId, using: client)
            } catch is CancellationError {
                // Sheet dismissed mid-poll — stop silently, don't surface an error.
            } catch {
                if !Task.isCancelled { self.state = .error(error.localizedDescription) }
            }
        }
    }

    /// Cancel any in-flight preview poll. Called from ImportView.onDisappear.
    func stop() {
        previewTask?.cancel()
        previewTask = nil
    }

    /// POST /spotify/import using the completed preview data.
    /// `canAcquire` false: the playlist is made from songs already on the server and nothing is downloaded.
    func confirmImport(using client: KimaAPIClient, canAcquire: Bool) async {
        guard let preview = previewResult, let jobId = previewJobId, canConfirm else { return }

        state = .confirming
        let name = playlistName.trimmingCharacters(in: .whitespaces)
        let mbids = canAcquire ? preview.albumsToDownload.map(\.downloadId) : []

        do {
            let r = try await client.startImport(
                spotifyPlaylistId: preview.playlist.id,
                playlistName: name,
                albumMbidsToDownload: mbids,
                previewJobId: jobId
            )
            state = .done(jobId: r.jobId)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// POST /spotify/import/quick — bypasses preview, fires off the import immediately.
    func startQuickImport(using client: KimaAPIClient) async {
        let url = urlText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty, !isBusy, !isDone else { return }
        state = .confirming
        do {
            let jobId = try await client.quickImport(url: url, playlistName: nil)
            state = .done(jobId: jobId)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Reset to idle, preserving the URL so the user can tweak and retry.
    func reset() {
        playlistName = ""
        state = .idle
        previewResult = nil
        previewJobId = nil
    }

    // MARK: - Private

    /// Poll every 1.5 s, up to 60 times (≈ 90 s), until status leaves "pending".
    private func pollPreview(jobId: String, using client: KimaAPIClient) async throws {
        for _ in 0..<60 {
            try await Task.sleep(for: .seconds(1.5))
            let result = try await client.getPreviewResult(jobId: jobId)
            guard result.status != "pending" else { continue }
            if result.status == "completed", let p = result.preview {
                previewResult = p
                playlistName = p.playlist.name
                state = .previewReady
                return
            }
            state = .error(result.error ?? "preview failed. please try again.")
            return
        }
        state = .error("preview timed out. the playlist may be very large — try quick import.")
    }
}
