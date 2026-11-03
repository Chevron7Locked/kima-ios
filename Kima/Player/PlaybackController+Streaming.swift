import Foundation

extension PlaybackController {
    /// The `?token=` credential for a stream URL — see `KimaAPIClient.streamTicket()`. nil = no stream can be built.
    func resolveStreamToken(_ client: KimaAPIClient?) async -> String? {
        await client?.streamTicket()
    }

    /// Mint a stream ticket before the user taps anything.
    ///
    /// Every play path ends in `loadStream` → `resolveStreamToken` → `streamTicket()`, so the
    /// first play of a session pays a full round trip before the player is handed a URL — the
    /// tap feels dead for reasons that have nothing to do with what was tapped. `streamTicket()`
    /// is cached to a TTL/2 renewal point and single-flight, so calling it ahead of the tap
    /// moves that round trip off the tap and costs nothing on repeat calls.
    func startKeepingStreamTicketWarm() {
        guard ticketWarmTask == nil, let client = apiClient else { return }
        ticketWarmTask = Task { [weak self] in
            while !Task.isCancelled {
                // nil means the server refused (signed out, refresh failed, no network): stop,
                // do not retry forever. The play path mints on demand, so stopping is never a
                // correctness cost — only the loss of a head start.
                let ticket = await client.streamTicket()
                guard ticket != nil, !Task.isCancelled else { break }
                // Renew on the cache's own schedule; five minutes when the server has no ticket
                // endpoint (nothing ever caches, so the delay is nil).
                let delay = await client.ticketRenewalDelay ?? 300
                try? await Task.sleep(nanoseconds: UInt64(max(30, delay) * 1_000_000_000))
            }
            // Back to the main actor to drop the handle: the loop's continuations resume on the
            // actor's executor, and `ticketWarmTask` is main-actor state. Clearing it lets
            // `startKeepingStreamTicketWarm()` start a fresh loop after a token rotation.
            await MainActor.run { [weak self] in self?.ticketWarmTask = nil }
        }
    }

    /// Stop the keeper. `AppEnvironment.teardown()` calls this on sign-out, so a released
    /// environment can never keep minting stream tickets for an app that is no longer signed in.
    func stopKeepingStreamTicketWarm() {
        ticketWarmTask?.cancel()
        ticketWarmTask = nil
    }

    /// Mint a stream token, then load `makeURL(token)` unless a newer load claimed the player meanwhile. The caller
    /// mints `claim` (`engine.claimLoad()`) first, so load intents are totally ordered. With no token or URL nothing
    /// loads and the user sees why; the login token is never a fallback. `prepare` runs before the mint;
    /// `beforeLoad` / `afterLoad` wrap `engine.load`.
    func loadStream(
        claim: Int, client: KimaAPIClient?, autoplay: Bool, seekTo: Double?,
        prepare: (@MainActor () async -> Void)? = nil,
        beforeLoad: (@MainActor () -> Void)? = nil,
        afterLoad: (@MainActor () -> Void)? = nil,
        makeURL: @escaping @MainActor (String) -> URL?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await prepare?()
            let token = await self.resolveStreamToken(client)
            guard self.engine.isCurrentLoad(claim) else { return }  // superseded — a newer intent owns the player
            guard let token, let url = makeURL(token) else {
                let expired = token == nil ? await self.sessionHasExpired(client) : false
                guard self.engine.isCurrentLoad(claim) else { return }
                self.engine.signalExternalError(expired
                    ? "session expired. please sign in again."
                    : "can't reach your server. tap play to try again.")
                return
            }
            beforeLoad?()
            self.engine.load(url: url, autoplay: autoplay, seekTo: seekTo)
            afterLoad?()
        }
    }

    /// True only when the server says the sign-in is no longer valid (after the client's own token
    /// refresh failed). No answer within 5 s counts as still signed in.
    func sessionHasExpired(_ client: KimaAPIClient?) async -> Bool {
        guard let client else { return false }
        let probe = Task { await client.probeAuthMe() }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(5))
            probe.cancel()  // a cancelled probe answers "signed in"
        }
        defer { timeout.cancel() }
        return await !probe.value
    }
}
