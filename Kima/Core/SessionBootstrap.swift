import Foundation

// MARK: - Session bootstrap
// The signed-in session's network lifecycle, split out of AppEnvironment (ticket 12): the bag
// views read is inert to construct; this module owns when its streams and loops begin and end.
// RootView calls `start()` once the environment exists and `stop()` on `.unauthenticated` before
// releasing it — one call each, ordering guaranteed in here, not by a comment in the root view.

/// Starts and stops the network lifecycle of one authenticated session: the warm stream-ticket
/// keeper, playback-state polling, the event stream, cover-art auth wiring, and the token-rotation
/// observer that keeps the warm ticket following the token. Lives as long as the
/// `AppEnvironment` it serves; constructed inert like it.
@MainActor
final class SessionBootstrap {
    private let server: KimaServer
    private let client: KimaAPIClient
    private let player: PlaybackController
    private let sync: PlaybackSyncCoordinator
    private let events: SSEManager

    /// NotificationCenter token for the rotation observer; removed in `stop()`. An environment
    /// released without signing out needs no explicit removal: the block captures `self` weakly,
    /// so it goes inert at once and NotificationCenter releases it together with this object.
    private var tokenObserver: NSObjectProtocol?

    /// One lifecycle per bootstrap: RootView may hand `start()` to a second window that joins
    /// the live environment, and a repeat call must open nothing new.
    private var hasStarted = false

    init(server: KimaServer, client: KimaAPIClient, player: PlaybackController,
         sync: PlaybackSyncCoordinator, events: SSEManager) {
        self.server = server
        self.client = client
        self.player = player
        self.sync = sync
        self.events = events
    }

    /// Begin the session's network lifecycle. Idempotent — and terminal after `stop()`: a
    /// stopped bootstrap never restarts; a re-login builds a fresh environment. The pieces
    /// self-order: `syncHook` and `apiClient` were wired when the environment was built, so no
    /// mutation event is missed between construction and here.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        // Mint the stream ticket ahead of the first tap: every play path mints one inline, so the
        // first play of a session would otherwise pay a round trip before the player gets a URL.
        // The environment is authenticated-scope (see AppEnvironment), so this is a mint at sign-in.
        player.startKeepingStreamTicketWarm()
        sync.start()
        // Start the SSE stream; the manager also fires an initial refreshNotifications() Task.
        events.start(client: client, server: server)
        // Configure ImageCache to send the auth header on cover-art requests to our server.
        // The closure captures `client` (the actor), re-reading the credential on each miss
        // so token refreshes and login/logout are handled without re-configuring — and not
        // `self`, or the global cache would outlive the session that started it.
        let client = self.client
        Task { await ImageCache.shared.configure(serverHost: server.baseURL.host(percentEncoded: false)) { await client.authHeader() } }
        // Observe token rotations so the cached stream ticket is dropped. Weak capture
        // prevents a retain cycle (block → self → tokenObserver → block). After the bootstrap
        // deinits, the guard ensures the block is a no-op until the next NotificationCenter GC
        // removes it.
        tokenObserver = NotificationCenter.default.addObserver(
            forName: .kimaAccessTokenRotated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue: .main delivers on the main queue, but the block is a
            // nonisolated context — hop so the mutation of the @MainActor state is
            // isolation-checked (compiler warning otherwise).
            Task { @MainActor [weak self] in
                // Also drop the cached stream ticket so the next play request fetches a fresh one.
                await self?.client.invalidateStreamTicket()
                // And re-mint now: the warm ticket has to follow the new token, and the keeper's
                // own sleep runs to half the ticket's lifetime — hours, for a 4-hour ticket.
                self?.player.stopKeepingStreamTicketWarm()
                self?.player.startKeepingStreamTicketWarm()
            }
        }
    }

    /// End the lifecycle in its one safe order: the event stream first (its reconnect loop would
    /// otherwise mint through a client whose session is ending), then the state poll, then the
    /// ticket keeper, then the rotation observer. RootView calls this on `.unauthenticated` before
    /// releasing the environment — Swift-6 @MainActor deinit can't do teardown itself (see
    /// SSEManager.swift).
    func stop() {
        events.teardown()
        sync.stop()
        // Stop minting stream tickets ahead of taps: the env is about to be released and the app
        // is signed out, so there is no session left to warm.
        player.stopKeepingStreamTicketWarm()
        if let obs = tokenObserver {
            NotificationCenter.default.removeObserver(obs)
            tokenObserver = nil
        }
    }
}
