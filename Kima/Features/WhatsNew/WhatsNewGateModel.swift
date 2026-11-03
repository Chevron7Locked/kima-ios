import Foundation
import Observation

// MARK: - What's-new gate model
// The server decides what is pending (`GET /whats-new/pending`); nothing is recorded locally, so a second device
// asks too. The fetch runs once per signed-in session (this model lives on AppEnvironment, rebuilt on sign-in);
// a failed fetch is not cached and retries next time. The queue shows oldest first, one release at a time.

@MainActor
@Observable
final class WhatsNewGateModel {
    private(set) var queue: [WhatsNewRelease] = []
    private(set) var isLoading = false

    /// The release currently on screen (`queue.first` once loaded).
    var current: WhatsNewRelease? { queue.first }

    private var loaded = false
    private var loadingTask: Task<Void, Never>?

    private let client: KimaAPIClient

    init(client: KimaAPIClient) {
        self.client = client
    }

    /// Load the queue once per session. No-op once loaded — AppShellView may
    /// call this from every first appearance.
    func loadOnce() async {
        if loaded { return }
        #if DEBUG
        // UI suites whose subject sits behind the gate's full-screen sheet pass
        // `-kima-no-whatsnew` (see DebugCardPlayDelay.swift); never set in normal use.
        if DebugNoWhatsNew.enabled {
            loaded = true
            return
        }
        #endif
        if let loadingTask { await loadingTask.value; return }
        loadingTask = Task { [weak self] in
            guard let self else { return }
            self.isLoading = true
            defer { self.isLoading = false }
            do {
                let releases = try await self.client.getWhatsNewPending()
                self.queue = releases
                self.loaded = true          // only a success caches (web parity)
            } catch {
                // Never block the app on this — someone came to listen to
                // music. Logged for probes; the next launch/apppearance retries.
                #if DEBUG
                print("[WhatsNew] pending fetch failed (stays pending): \(error)")
                #endif
            }
            self.loadingTask = nil
        }
        await loadingTask?.value
    }

    /// Drop the shown release from the queue (the window closed and the server
    //  recorded the dismissal — the sheet only calls this after a successful
    //  dismiss POST, matching the web's close() ordering).
    func closeCurrent() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
    }

    /// "Take me to it" — the remaining windows are deferred for this app
    /// session, so they don't follow the user to the page they navigated to
    /// (web parity: sessionStorage `whatsnew.deferred`, cleared with the tab).
    func deferRest() {
        queue = []
    }

    /// DEBUG probe hook: replaces the queue with a synthetic one as if the server answered, to exercise the
    /// window UI without seeded release rows. It replaces unconditionally because a dev simulator's live session
    /// would make the probe non-deterministic; it runs after loadOnce, so no in-flight fetch is lost.
    #if DEBUG
    func debugInject(_ releases: [WhatsNewRelease]) {
        loaded = true
        queue = releases
    }
    #endif
}
