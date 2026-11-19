import Foundation

// MARK: - Stream source
// The one module that answers playable URLs (ticket 13): minting the short-lived stream ticket,
// caching it until near its half-life, keeping soon-to-play tracks warm, and dropping cached
// tickets when credentials rotate all live here, and the renewal timing exists in exactly this
// file. Player paths and page preview rows ask for a playable URL — nobody outside this module
// ever sees a ticket or assembles a stream URL (ticket 14).

/// The stream source's clock: wall time and real sleeps in production; tests inject virtual time
/// so the renewal schedule is asserted, not waited out (same posture as `SSEManager.backoffDelay`).
/// A throwing `sleep` ends the keeper loop — cancellation wakes the production sleep the same way.
struct StreamClock {
    var now: @Sendable () -> Date
    var sleep: @Sendable (Duration) async throws -> Void

    static let live = StreamClock(now: { Date.now }, sleep: { try await Task.sleep(for: $0) })
}

@MainActor
final class StreamSource {
    private let server: KimaServer
    private let client: KimaAPIClient
    private let clock: StreamClock

    /// Cached stream ticket and its renewal point — half the TTL after mint, never later than the
    /// absolute 60 s pre-expiry deadline for pathological tiny TTLs. Renewing at TTL/2 rather than
    /// only in the last minute means a stream started 3h59m into a cached ticket can't be
    /// scheduled to die mid-song when the server enforces expiry on the live connection.
    private var cached: (ticket: String, renewsAt: Date)?

    /// In-flight stream-ticket mint; nil when none is running. Single-flight shares it with every
    /// ask that arrives meanwhile — the `refreshTask` pattern, one fewer round trip per burst.
    private var ticketTask: Task<String?, Never>?

    /// The warm-ticket loop and the rotation observer that remakes it; both ended by `stop()`.
    private var keeperTask: Task<Void, Never>?
    private var rotationObserver: NSObjectProtocol?

    /// Bumped on every keeper (re)start. A woken cancelled loop clears its own handle only while
    /// its generation is still current — the bug this guards: a rotation restart lets the old
    /// parked task wake on cancellation and nil out the NEW keeper's handle, orphaning it.
    private var keeperGeneration = 0

    init(server: KimaServer, client: KimaAPIClient, clock: StreamClock = .live) {
        self.server = server
        self.client = client
        self.clock = clock
    }

    /// The answer to "what URL can AVPlayer play right now?": a URL carrying a stream ticket, or
    /// why there isn't one. `noTicket` keeps the player's established distinction between a dead
    /// session (worth an /auth/me probe) and an unreachable server (just a message).
    enum Answer {
        case url(URL)
        /// The mint failed (signed out, refresh failed, no network): no stream credential exists.
        case noTicket
        /// A ticket was held but the URL wouldn't build — nothing to blame the login for.
        case badURL
    }

    // MARK: - Playable URLs

    /// Track stream URL — hits the server, triggering a server-side Play row (scrobble).
    func playableURL(trackId: String) async -> Answer {
        await answer { StreamURL.track(base: $0, trackId: trackId, token: $1) }
    }

    /// Audiobook file stream URL — `trackIndex` omitted when `index` is 0 (server plays the first file).
    func playableURL(bookId: String, index: Int) async -> Answer {
        await answer { StreamURL.audiobook(base: $0, bookId: bookId, index: index, token: $1) }
    }

    /// Podcast episode stream URL.
    func playableURL(podcastId: String, episodeId: String) async -> Answer {
        await answer { StreamURL.podcastEpisode(base: $0, podcastId: podcastId, episodeId: episodeId, token: $1) }
    }

    /// A not-followed show's first episode snippet, streamed through the server and stored nowhere.
    func playableURL(sampleItunesId itunesId: String) async -> Answer {
        await answer { StreamURL.podcastSnippet(base: $0, itunesId: itunesId, token: $1) }
    }

    /// The 30-second preview clip of a missing/unowned track, via the server's on-the-fly preview
    /// proxy. Page rows (album, browse-playlist, artist) ask this — like every answer here it
    /// rides a stream ticket when one can be minted; `.noTicket` is the page's cue to fall back
    /// to its payload's raw link or offer nothing.
    func previewURL(artistName: String, trackTitle: String) async -> Answer {
        await answer { PreviewURL.track(base: $0, artistName: artistName, trackTitle: trackTitle, token: $1) }
    }

    /// The one shape every answer shares: hold a ticket, then build. Callers pass ids, never see
    /// a ticket, and never assemble a stream URL themselves.
    private func answer(_ build: (KimaServer, String) -> URL?) async -> Answer {
        guard let ticket = await ticket() else { return .noTicket }
        guard let url = build(server, ticket) else { return .badURL }
        return .url(url)
    }

    /// Drops the cached ticket so the next answer re-mints. Called before rebuilding a stream
    /// after a mid-stream failure — a clock-valid ticket the server just rejected would fail the
    /// rebuild too — and on every token rotation.
    func dropTicket() { cached = nil }

    // MARK: - Warm keeper and rotation-drop

    /// Opens the session's ticket lifecycle: one mint right away, so the first tap of a session
    /// doesn't pay the mint round trip before the player gets a URL, then kept warm to each
    /// ticket's renewal point. SessionBootstrap calls this once at sign-in; `stop()` ends it.
    func start() {
        observeRotations()
        remakeKeeper()
    }

    /// Ends the keeper and the rotation observer: there is no session left to warm, and a stopped
    /// source mints for none — rotated tokens included. A re-login builds a fresh source, same
    /// terminal-stop discipline as SessionBootstrap.
    func stop() {
        keeperTask?.cancel()
        keeperTask = nil
        if let rotationObserver {
            NotificationCenter.default.removeObserver(rotationObserver)
            self.rotationObserver = nil
        }
    }

    /// When the cached ticket needs replacing, in seconds — nil when nothing is cached. A server
    /// without the ticket endpoint caches nothing, so the keeper re-checks on a fixed rhythm
    /// rather than never again.
    private var renewalDelay: TimeInterval? {
        cached.map { max(0, $0.renewsAt.timeIntervalSince(clock.now())) }
    }

    /// The renewal schedule stated once in this file, so no caller can re-spell it: sleep to the
    /// ticket's renewal point — never below 30 s (a pathological tiny TTL must not spin the
    /// loop) — and a ticketless server every five minutes. A refused mint ends the loop: there is
    /// no session left to warm, the play path still mints on demand, and rotation or the next
    /// sign-in starts this again.
    private func runKeeper(generation: Int) async {
        while !Task.isCancelled {
            guard await ticket() != nil else { break }
            let delay = max(30, renewalDelay ?? 300)
            do { try await clock.sleep(.seconds(delay)) }
            catch { break }   // cancelled by stop/rotation — or the test seam ends the cycle here
        }
        if keeperGeneration == generation { keeperTask = nil }   // only the current loop clears its handle
    }

    /// Starts a fresh keeper loop, cancelling the parked one: rotation's "follow this new token
    /// now" can't wait out a sleep half the ticket's lifetime — hours for a 4-hour ticket.
    private func remakeKeeper() {
        keeperTask?.cancel()
        keeperGeneration += 1
        let generation = keeperGeneration
        // A Task created in this @MainActor method inherits the isolation (Swift 6), so the loop
        // touching `cached`/`ticketTask` is safe. Weak capture: a released source must not mint forever.
        keeperTask = Task { [weak self] in await self?.runKeeper(generation: generation) }
    }

    /// While running, every token rotation drops the warm ticket — it was minted against the old
    /// token — and remakes the keeper. `.kimaAccessTokenRotated` comes from
    /// `KimaAPIClient.refreshAccessToken()` on rotation and on the wipe-after-failed-refresh.
    private func observeRotations() {
        guard rotationObserver == nil else { return }
        // Weak capture prevents a retain cycle (block → self → observer token → block);
        // queue: .main is a nonisolated context, so hop to mutate @MainActor state.
        rotationObserver = NotificationCenter.default.addObserver(
            forName: .kimaAccessTokenRotated, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dropTicket()
                self?.remakeKeeper()
            }
        }
    }

    // MARK: - Ticket mint

    /// The raw short-lived stream ticket, minted or taken from the cache. Private:
    /// every answer above builds on it, and nothing outside this module sees a ticket or assembles
    /// a `?token=` URL. On a 404 (server without the ticket endpoint) returns the login JWT, the
    /// only stream credential that server accepts; on any other failure returns nil, and callers
    /// must not substitute the login JWT.
    private func ticket() async -> String? {
        struct StreamTicketResponse: Decodable {
            let ticket: String
            let expiresIn: Int
        }
        // Cache hit: not yet at the proactive renewal point (see `cached`).
        if let cached, clock.now() < cached.renewsAt { return cached.ticket }
        // Single-flight: share an already-in-flight mint.
        if let existing = ticketTask { return await existing.value }
        // A Task created in this @MainActor method inherits the isolation (Swift 6), so reading
        // and writing `cached` inside it is safe.
        let task = Task<String?, Never> {
            do {
                // `post` carries the credential header and the 401→/auth/refresh→retry, same as
                // every other authed call.
                let response: StreamTicketResponse = try await self.client.post("/auth/stream-ticket", body: [:], authed: true)
                let mintedAt = self.clock.now()
                self.cached = (
                    ticket: response.ticket,
                    renewsAt: min(mintedAt.addingTimeInterval(TimeInterval(response.expiresIn) / 2),
                                  mintedAt.addingTimeInterval(TimeInterval(response.expiresIn) - 60))
                )
                return response.ticket
            } catch APIError.http(let status, _) where status == 404 {
                // Server predates stream tickets: the login JWT is the only stream credential it accepts.
                return KeychainStore.credential(KeychainStore.accessToken, for: self.server)
            } catch {
                return nil   // never fall back to the login JWT: it would sit in proxy logs as an all-scope credential
            }
        }
        ticketTask = task
        let result = await task.value
        ticketTask = nil
        return result
    }
}

extension StreamSource.Answer {
    /// The playable URL, or nil — for callers with nothing to offer on failure (album rows).
    /// Player paths switch on the cases: only they care whether a dead session is worth an
    /// /auth/me probe.
    var url: URL? {
        if case .url(let url) = self { return url }
        return nil
    }

    /// The answer's URL when there is one, else the payload's raw preview link — the shared
    /// no-answer fallback of the browse-playlist and artist rows (the raw Deezer link expires
    /// ~27 h after the server fetched it, so it never wins while a ticket can be minted). An
    /// empty or unparseable raw link answers nothing.
    func url(orRawLink raw: String?) -> URL? {
        if case .url(let url) = self { return url }
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}
