import Foundation

extension PlaybackController {
    /// Ask the stream source for a playable URL, then load the answer unless a newer load claimed
    /// the player meanwhile. The caller mints `claim` (`engine.claimLoad()`) first, so load intents
    /// are totally ordered. A refused mint ends in a terminal error with the queue kept — and the
    /// login token is never a fallback. `prepare` runs before the ask (a rebuild drops its rejected
    /// ticket there); `beforeLoad` / `afterLoad` wrap `engine.load`. `seekTo` is read when the load
    /// is issued, after the ask: a rebuild restarts at a skip made while its ticket was fetched.
    func loadStream(
        claim: Int, autoplay: Bool, seekTo: @escaping @MainActor () -> Double?,
        prepare: (@MainActor () async -> Void)? = nil,
        beforeLoad: (@MainActor () -> Void)? = nil,
        afterLoad: (@MainActor () -> Void)? = nil,
        ask: @escaping @MainActor (StreamSource) async -> StreamSource.Answer
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await prepare?()
            // An unwired player (previews, silent test hosts) has no stream credential to ask for —
            // the same answer a refused mint gives.
            let answer: StreamSource.Answer
            if let source = self.streamSource {
                answer = await ask(source)
            } else {
                answer = .noTicket
            }
            guard self.engine.isCurrentLoad(claim) else { return }  // superseded — a newer intent owns the player
            switch answer {
            case .url(let url):
                beforeLoad?()
                self.engine.load(url: url, autoplay: autoplay, seekTo: seekTo())
                afterLoad?()
            case .noTicket:
                let expired = await self.sessionHasExpired(self.apiClient)
                guard self.engine.isCurrentLoad(claim) else { return }
                self.engine.signalExternalError(expired
                    ? "session expired. please sign in again."
                    : "can't reach your server. tap play to try again.")
            case .badURL:
                // A ticket was held but the URL wouldn't build — nothing to blame the login for.
                self.engine.signalExternalError("can't reach your server. tap play to try again.")
            }
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
