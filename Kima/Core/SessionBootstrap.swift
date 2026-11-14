import Foundation

// MARK: - Session bootstrap
// The signed-in session's network lifecycle, split out of AppEnvironment (ticket 12): the bag
// views read is inert to construct; this module owns when its streams and loops begin and end.
// RootView calls `start()` once the environment exists and `stop()` on `.unauthenticated` before
// releasing it — one call each, ordering guaranteed in here, not by a comment in the root view.

/// Starts and stops the network lifecycle of one authenticated session: the stream source (which
/// owns its warm-ticket keeper and rotation observer, ticket 13), playback-state polling, the event
/// stream, and cover-art auth wiring. Lives as long as the `AppEnvironment` it serves; constructed
/// inert like it.
@MainActor
final class SessionBootstrap {
    private let server: KimaServer
    private let client: KimaAPIClient
    private let stream: StreamSource
    private let sync: PlaybackSyncCoordinator
    private let events: SSEManager

    /// One lifecycle per bootstrap: RootView may hand `start()` to a second window that joins
    /// the live environment, and a repeat call must open nothing new.
    private var hasStarted = false

    init(server: KimaServer, client: KimaAPIClient, stream: StreamSource,
         sync: PlaybackSyncCoordinator, events: SSEManager) {
        self.server = server
        self.client = client
        self.stream = stream
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
        // Open the ticket lifecycle first: one mint right away so the first play of a session
        // doesn't pay a round trip before the player gets a URL. The environment is
        // authenticated-scope (see AppEnvironment), so this is a mint at sign-in.
        stream.start()
        sync.start()
        // Start the SSE stream; the manager also fires an initial refreshNotifications() Task.
        events.start(client: client, server: server)
        // Configure ImageCache to send the auth header on cover-art requests to our server.
        // The closure captures `client` (the actor), re-reading the credential on each miss
        // so token refreshes and login/logout are handled without re-configuring — and not
        // `self`, or the global cache would outlive the session that started it.
        let client = self.client
        Task { await ImageCache.shared.configure(serverHost: server.baseURL.host(percentEncoded: false)) { await client.authHeader() } }
    }

    /// End the lifecycle in its one safe order: the event stream first (its reconnect loop would
    /// otherwise mint through a client whose session is ending), then the state poll, then the
    /// stream source. RootView calls this on `.unauthenticated` before releasing the environment —
    /// Swift-6 @MainActor deinit can't do teardown itself (see SSEManager.swift).
    func stop() {
        events.teardown()
        sync.stop()
        // Stop minting stream tickets ahead of taps: the env is about to be released and the app
        // is signed out, so there is no session left to warm.
        stream.stop()
    }
}
