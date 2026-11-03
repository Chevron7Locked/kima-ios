import Foundation
import UIKit

// MARK: - SSE Engine
// Owns the long-lived GET /api/events stream, opened with a short-lived ticket instead of an Authorization header.
// @MainActor is fine: URLSession.bytes suspends cooperatively and events are sparse. Background stops the stream;
// foreground relaunches and refreshes once (SSE has no replay). RootView calls teardown() on logout.

@MainActor
@Observable
final class SSEManager {

    // MARK: - Observable state

    /// Ordered, non-cleared notifications. Refreshed on any notification SSE event and
    /// on foreground resume (SSE has no replay — a GET /notifications fills the gap).
    var notifications: [KimaNotification] = []

    /// Derived count of unread items. Updated together with `notifications`.
    var unreadCount: Int = 0

    /// True while the stream is open and heartbeats are flowing.
    var isConnected = false

    // Monotonic counters — increment on the matching event class. SwiftUI views observe
    // these with `.onChange(of: events.downloadTick)` to trigger per-view VM refetches.
    var downloadTick = 0
    var discoverTick = 0
    var importTick = 0

    /// Bumped when library contents may have changed (a scan finished, enrichment moved on), at most
    /// once per `libraryRefreshSpacing`, so a long run of events can't set off a reload storm.
    var libraryTick = 0
    @ObservationIgnored var libraryRefreshSpacing: Duration = .seconds(10)
    @ObservationIgnored private var libraryTickPending = false

    /// The latest library scan event, for the More menu's sync row.
    struct ScanEvent: Equatable {
        let jobId: String?
        let progress: Double
        let finished: Bool
        let failed: Bool
    }
    var lastScan: ScanEvent?

    // MARK: - Private stream state

    @ObservationIgnored private var streamTask: Task<Void, Never>?

    /// Dedicated URLSession for the SSE connection. Ephemeral (no disk cache) with
    /// unlimited timeouts; the OS must not tear down the persistent long-lived connection.
    @ObservationIgnored private let sseSession: URLSession

    /// Retained for foreground-resume restart and notification-action methods.
    @ObservationIgnored var storedClient: KimaAPIClient?
    @ObservationIgnored private var storedServer: KimaServer?

    /// NotificationCenter lifecycle observer tokens (background / foreground).
    @ObservationIgnored private var backgroundToken: NSObjectProtocol?
    @ObservationIgnored private var foregroundToken: NSObjectProtocol?

    /// Single-flight guard for notification refreshes. A burst of SSE events (e.g. several
    /// notification + connected events in quick succession) would otherwise spawn N overlapping
    /// GET /notifications requests. The first caller proceeds; subsequent callers return
    /// immediately and rely on the in-flight request to update the shared state.
    @ObservationIgnored var refreshInFlight = false

    // MARK: - Init

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        // Finite (not Int.max): a silently-dead connection (server gone, no FIN) must eventually
        // time out so the reconnect loop fires instead of hanging forever. Request timeout is the
        // max gap between bytes — longer than the server's SSE keepalive; resource forces a daily
        // reconnect. Both let the OS reclaim hung sockets.
        cfg.timeoutIntervalForRequest = 600        // 10 min inactivity → error → reconnect
        cfg.timeoutIntervalForResource = 86_400    // 1 day max stream lifetime → clean reconnect
        sseSession = URLSession(configuration: cfg, delegate: ServerTrustCoordinator.shared, delegateQueue: nil)
    }

    // No deinit cleanup on purpose: in Swift 6 deinit is non-isolated, so touching the @MainActor `streamTask`
    // there is a compiler error. RootView calls teardown() on .unauthenticated before releasing AppEnvironment,
    // which cancels the stream on the main actor.

    // MARK: - Public API

    /// Start the SSE stream. Call once from AppEnvironment.init after the client is ready.
    /// Subsequent calls replace the active stream (safe to call on server-switch).
    func start(client: KimaAPIClient, server: KimaServer) {
        storedClient = client
        storedServer = server
        registerLifecycleObservers()
        launchStream(client: client, server: server)
        Task { [weak self] in await self?.refreshNotifications() }
    }

    /// Cancel the active stream without removing lifecycle observers or clearing stored
    /// client/server. Used when entering background; the foreground observer will restart.
    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isConnected = false
    }

    /// Full teardown: cancel stream and remove lifecycle observers. Call from RootView on
    /// `.unauthenticated` before setting AppEnvironment to nil (see init note above).
    func teardown() {
        stop()
        if let t = backgroundToken {
            NotificationCenter.default.removeObserver(t)
            backgroundToken = nil
        }
        if let t = foregroundToken {
            NotificationCenter.default.removeObserver(t)
            foregroundToken = nil
        }
    }

    // MARK: - Private stream management

    private func launchStream(client: KimaAPIClient, server: KimaServer) {
        streamTask?.cancel()
        // Task { } inherits @MainActor from this call site (Swift 6). Awaiting network I/O
        // inside suspends the actor cooperatively — the main thread is NOT blocked.
        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.runReconnectLoop(client: client, server: server)
        }
    }

    private func runReconnectLoop(client: KimaAPIClient, server: KimaServer) async {
        var backoff: UInt64 = 1_000_000_000      // 1 second
        let maxBackoff: UInt64 = 30_000_000_000  // 30 seconds cap

        while !Task.isCancelled {
            do {
                // Mint a fresh ticket for each connection attempt. Tickets are single-use
                // and short-lived; the POST is authed, the stream URL is not.
                let ticket = try await client.eventsTicket()
                guard !Task.isCancelled else { break }

                let url = server.api("/events", query: ["ticket": ticket])
                var req = URLRequest(url: url)
                req.cachePolicy = .reloadIgnoringLocalCacheData

                let (bytes, response) = try await sseSession.bytes(for: req)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                // Auth failures on the stream endpoint are terminal — the ticket was rejected
                // or the session was revoked. Bail immediately rather than spinning on backoff.
                if http.statusCode == 401 || http.statusCode == 403 {
                    isConnected = false
                    postAuthFailed()
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                isConnected = true
                backoff = 1_000_000_000  // reset on successful connection

                // Byte-level framing: bytes.lines drops the blank line that ends each event.
                // The server sends every event as the default "message" type with the event name
                // in the JSON body as `data.type` (mirrors the web EventSource.onmessage).
                var parser = SSEFrameParser()
                for try await byte in bytes {
                    guard !Task.isCancelled else { break }
                    if let event = parser.feed(byte) { handle(data: event.data) }
                }

            } catch let apiErr as APIError {
                // Auth failures from the ticket mint are terminal — the session is expired
                // or the token has been revoked. Stop retrying and signal the shell.
                let isAuthFailure: Bool
                switch apiErr {
                case .unauthorized: isAuthFailure = true
                case .http(status: let s, _) where s == 403: isAuthFailure = true
                default: isAuthFailure = false
                }
                if isAuthFailure {
                    isConnected = false
                    postAuthFailed()
                    return
                }
                // Other API errors (network, decoding, non-auth HTTP) are transient → reconnect.
            } catch {
                // Network loss, server close, timeout, cancellation — transient → reconnect.
            }

            guard !Task.isCancelled else { break }
            isConnected = false

            try? await Task.sleep(nanoseconds: backoff)
            backoff = min(backoff * 2, maxBackoff)
        }

        isConnected = false
    }

    /// Posts `kimaSSEAuthFailed` so the shell can surface a re-authentication prompt.
    /// Called when a 401/403 from the ticket mint or the stream endpoint makes further
    /// reconnection attempts pointless.
    private func postAuthFailed() {
        NotificationCenter.default.post(name: .kimaSSEAuthFailed, object: nil)
    }

    // MARK: - Library changes

    /// Bumps `libraryTick` once `libraryRefreshSpacing` after the first of a run of events.
    private func noteLibraryChanged() {
        guard !libraryTickPending else { return }
        libraryTickPending = true
        let spacing = libraryRefreshSpacing
        Task { [weak self] in
            try? await Task.sleep(for: spacing)
            guard let self else { return }
            self.libraryTickPending = false
            self.libraryTick += 1
        }
    }

    // MARK: - SSE event dispatch

    /// Handle a fully-parsed SSE event. Runs on @MainActor (same isolation as the Task).
    /// Async work (notification refresh) is dispatched as a new Task to avoid blocking
    /// the stream loop at each event. Internal for tests.
    func handle(data: String) {
        guard let jsonData = data.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let type = payload["type"] as? String else {
            return  // malformed payload or SSE comment that slipped through
        }

        switch type {
        case "notification", "notification:cleared":
            // Refresh gives the authoritative list; the SSE payload alone may not carry
            // all fields. The web invalidates its React Query cache on these same events.
            Task { [weak self] in await self?.refreshNotifications() }

        case "download:progress", "download:queued", "download:complete", "download:failed":
            downloadTick += 1

        case "discover:progress", "discover:complete":
            discoverTick += 1

        case "import:progress":
            importTick += 1

        case "scan:progress":
            lastScan = ScanEvent(jobId: payload["jobId"] as? String,
                                 progress: (payload["progress"] as? Double) ?? 0, finished: false, failed: false)

        case "scan:complete":
            lastScan = ScanEvent(jobId: payload["jobId"] as? String, progress: 100,
                                 finished: true, failed: payload["error"] != nil)
            noteLibraryChanged()

        case "enrichment:progress":
            noteLibraryChanged()

        case "connected":
            // Server sends "connected" on initial handshake and on reconnect.
            // Always refresh — SSE has no replay so the gap since last connect is unknown.
            isConnected = true
            Task { [weak self] in await self?.refreshNotifications() }

        default:
            break
        }
    }

    // MARK: - App lifecycle

    private func registerLifecycleObservers() {
        // Guard against double-registration if start() is called more than once.
        guard backgroundToken == nil else { return }

        backgroundToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Matches the pattern used in PlaybackController+LongFormHelpers.swift.
            Task { @MainActor [weak self] in self?.stop() }
        }

        foregroundToken = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let client = self.storedClient,
                      let server = self.storedServer else { return }
                self.launchStream(client: client, server: server)
                await self.refreshNotifications()
            }
        }
    }
}
