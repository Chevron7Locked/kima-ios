import Foundation
import Observation
import os.log

// MARK: - Loading and the computing poll
//
// Split out of VibeMapViewModel (346 lines, one class, six jobs). Methods only: every stored
// property stays in the class, because Swift does not allow stored properties in extensions.
// Same code, same names, same order of calls; the private helpers these used are now internal
// so a second file can reach them.

extension VibeMapViewModel {

    // MARK: - Data loading

    /// Interval between map polls while the server is computing the projection.
    static let pollIntervalNs: UInt64 = 4_000_000_000

    /// Poll ceiling: ~15 min. A projection stuck in "computing" past that is a server
    /// problem, and an endless spinner would hide it.
    static let pollCapSeconds: TimeInterval = 15 * 60

    /// Inits state, then fetches once; a `.computing` answer hands off to the 4s poll loop.
    func load(client: KimaAPIClient) async {
        pollTask?.cancel()
        selectedTrackId = nil
        isComputing = false
        // Keep a loaded map on screen: the same map must not replay its reveal.
        if case .loaded = phase {} else { phase = .loading }
        do {
            switch try await client.getVibeMap() {
            case .ready(let response):
                apply(response)
            case .computing:
                startPolling(client: client, keepStale: false)
            }
        } catch {
            if case .loaded = phase { return }
            phase = .failed(VibeErrorCopy.mapLoad(error))
        }
    }

    /// Called on every reopen instead of `load(client:)`. A loaded map stays on screen while the
    /// request runs, so there is no spinner flash; a `.computing` answer keeps it and polls silently.
    /// Selection is reset on each open.
    func backgroundRevalidate(client: KimaAPIClient) async {
        pollTask?.cancel()
        selectedTrackId = nil
        // Do NOT set phase = .loading here — lets existing data stay on screen.
        do {
            switch try await client.getVibeMap() {
            case .ready(let response):
                isComputing = false
                apply(response)
            case .computing:
                startPolling(client: client, keepStale: true)
            }
        } catch {
            // Only transition to failed on initial load (nothing to show yet).
            if case .loading = phase { phase = .failed(VibeErrorCopy.mapLoad(error)) }
            // Otherwise keep stale data — a silent refresh failure is better than an error flash.
        }
    }

    // MARK: - Computing poll (server 202 contract)

    /// Stops the computing-poll loop when the map closes. The model outlives the screen, so
    /// without this a poll would keep hitting the map endpoint until its cap.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        // The loop's last `isComputing = false` only runs on natural exit paths;
        // a cancel mid-await never reaches them, and a session-scoped VM stuck at
        // isComputing mutes revalidate ("not idle anymore" — poll doc above).
        isComputing = false
    }

    /// Polls `getVibeMap()` every 4s (cancel-safe; a new load/revalidate cancels the
    /// previous loop) until the server answers 200, the ~15min cap expires, or the task
    /// is detached. Transient fetch errors mid-poll are swallowed — the endpoint can
    /// 500 while the projection is mid-recompute; the cap is the escape hatch.
    func startPolling(client: KimaAPIClient, keepStale: Bool) {
        pollTask?.cancel()
        isComputing = true
        let started = Date.now
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var polls = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollIntervalNs)
                guard !Task.isCancelled else { return }
                polls += 1
                vibeMapLog.debug("vibe map: poll #\(polls) (still computing)")
                do {
                    if case .ready(let response) = try await client.getVibeMap() {
                        vibeMapLog.debug("vibe map: ready after \(polls) poll(s)")
                        self.isComputing = false
                        self.apply(response)
                        return
                    }
                } catch {
                    // A cancelled poll (dismiss / revalidate) lands here as
                    // URLError(.cancelled)/CancellationError — that is the loop being
                    // retired, not the map fetch failing; never flag it .failed.
                    if error is CancellationError || (error as? URLError)?.code == .cancelled {
                        return
                    }
                    if case .loading = self.phase {
                        // First load and the map fetch now fails outright — surface it.
                        self.isComputing = false
                        self.phase = .failed(VibeErrorCopy.mapLoad(error))
                        return
                    }
                    // Stale data on screen: keep polling; a silent failure beats an error flash.
                }
                if Date.now.timeIntervalSince(started) > Self.pollCapSeconds {
                    vibeMapLog.debug("vibe map: poll cap (~15 min) reached")
                    self.isComputing = false
                    if !keepStale, case .loading = self.phase {
                        self.phase = .failed(VibeErrorCopy.mapPollCap)
                    }
                    return
                }
            }
        }
    }
}
