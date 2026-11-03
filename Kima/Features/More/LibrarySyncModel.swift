import Foundation
import Observation

/// Runs a library scan from the More menu: starts it, then polls its progress every 2 s until it
/// finishes. Gives up on the progress (not the scan) after 10 failed polls in a row. Live scan
/// events (`apply`) update the row at once, including for a scan started somewhere else.
@MainActor
@Observable
final class LibrarySyncModel {
    enum State: Equatable {
        case idle
        case starting
        case scanning(Double)
        case done
        case failed(String)
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?
    /// The job this model started; events for another job are ignored while it runs.
    private var jobId: String?
    private let pollInterval: Duration

    init(pollInterval: Duration = .seconds(2)) { self.pollInterval = pollInterval }

    var isRunning: Bool {
        switch state {
        case .starting, .scanning: return true
        default: return false
        }
    }

    /// The line under "sync library".
    var description: String {
        switch state {
        case .idle: return "scan your music folder for new files"
        case .starting: return "starting the scan…"
        case .scanning(let p): return p > 0 ? "scanning — \(Int(min(p, 100)))%" : "scanning…"
        case .done: return "scan finished. new music is analysed in the background"
        case .failed(let message): return message
        }
    }

    func start(client: KimaAPIClient) {
        guard !isRunning else { return }
        state = .starting
        let interval = pollInterval
        // Holds the model weakly between polls so a closed screen is not kept alive by its own scan.
        task = Task { [weak self] in
            let jobId: String
            do {
                jobId = try await client.libraryScan().jobId
            } catch {
                if !Task.isCancelled { self?.state = .failed("couldn't start the library scan") }
                return
            }
            guard !Task.isCancelled else { return }
            self?.jobId = jobId
            self?.state = .scanning(0)
            var failedPolls = 0
            while !Task.isCancelled {
                let result: Result<LibraryScanStatus, Error>
                do { result = .success(try await client.libraryScanStatus(jobId: jobId)) } catch { result = .failure(error) }
                guard !Task.isCancelled, let self else { return }
                if self.handle(result, failedPolls: &failedPolls) { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Applies a live scan event. A finished scan ends the polling too.
    func apply(_ event: SSEManager.ScanEvent) {
        if isRunning, let jobId, let eventJob = event.jobId, eventJob != jobId { return }
        if event.finished {
            task?.cancel()
            task = nil
            jobId = nil
            state = event.failed ? .failed("the library scan failed") : .done
        } else if state != .starting {
            state = .scanning(event.progress)
        }
    }

    /// Stops polling (the scan itself keeps running on the server). Called when the screen goes away.
    func cancel() {
        task?.cancel()
        task = nil
        if isRunning { state = .idle }
    }

    /// Applies one poll answer. True when polling is over.
    private func handle(_ result: Result<LibraryScanStatus, Error>, failedPolls: inout Int) -> Bool {
        switch result {
        case .success(let status):
            failedPolls = 0
            switch status.status {
            case "completed": state = .done; return true
            case "failed": state = .failed("the library scan failed"); return true
            default: state = .scanning(status.progress ?? 0); return false
            }
        case .failure:
            failedPolls += 1
            guard failedPolls >= 10 else { return false }
            state = .failed("lost contact with the server. the scan may still be running")
            return true
        }
    }
}
