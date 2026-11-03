import Foundation
import os.log

/// Timing for every decoded API call: `networkMs` is what the server held us for, `decodeMs`
/// is what turning its bytes into models cost. "Tapping play is slower than the server takes"
/// is answered by this one log category.
let apiTimingLog = Logger(subsystem: "com.chevron7locked.kima", category: "api-timing")

/// Whole milliseconds since `start`, for the api-timing log.
func apiDurationMs(since start: ContinuousClock.Instant) -> Int {
    let c = start.duration(to: .now).components
    return Int(c.seconds) * 1000 + Int(c.attoseconds / 1_000_000_000_000_000)
}

/// Talks to one Kima server: builds requests, attaches auth, decodes JSON, maps errors.
/// An actor so credential state is safe across concurrent calls.
actor KimaAPIClient {
    let server: KimaServer
    private var credential: KimaCredential?
    private let session: URLSession
    /// Dedicated long-timeout session for calls whose server-side work can exceed the default
    /// request timeout (e.g. Soulseek P2P downloads, which block up to ~120s server-side while
    /// the transfer completes). Mirrors `makeDefaultSession()` — ephemeral, no disk cache — but
    /// with a longer `timeoutIntervalForRequest`. Same lifetime as `session`; built once per client.
    private let longSession: URLSession = KimaAPIClient.makeLongTimeoutSession()
    private let decoder = JSONDecoder()

    /// In-flight token refresh. Nil when no refresh is running. Concurrent 401 callers await
    /// this shared Task to guarantee exactly one /auth/refresh round-trip at a time (single-flight).
    private var refreshTask: Task<String, any Error>?

    /// Cached stream ticket, its expiry, and the renewal point (half the TTL after mint), so a stream built from
    /// this cache always has at least half its lifetime left and never expires mid-song.
    /// Internal, not private: streamTicket() in the +LongForm extension reads and writes it.
    var cachedStreamTicket: (ticket: String, expiry: Date, renewsAt: Date)?

    /// In-flight stream-ticket fetch; nil when none is running.
    /// Mirrors `refreshTask` single-flight pattern: concurrent callers share one Task.
    /// internal (not private): shared with the +LongForm extension file.
    var ticketTask: Task<String?, Never>?

    /// Builds a dedicated ephemeral URLSession: no persistent disk cache, no persistent cookie
    /// store. Prevents authenticated API responses (user profile, library contents, play history)
    /// from being written to `Library/Caches/` where they are readable without the JWT.
    ///
    private static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral  // no disk cache; no persistent cookies
        return URLSession(configuration: config, delegate: ServerTrustCoordinator.shared, delegateQueue: nil)
    }

    /// Same ephemeral posture as `makeDefaultSession()`, but with a 180s request timeout —
    /// covers the Soulseek download endpoint's ~120s server-side P2P transfer budget, which
    /// exceeds the default session's 60s timeout. Mirrors the dedicated long-lived session
    /// `SSEManager` builds for its own long-running connection.
    private static func makeLongTimeoutSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral  // no disk cache; no persistent cookies
        config.timeoutIntervalForRequest = 180
        return URLSession(configuration: config, delegate: ServerTrustCoordinator.shared, delegateQueue: nil)
    }

    init(server: KimaServer, credential: KimaCredential? = nil, session: URLSession = KimaAPIClient.makeDefaultSession()) {
        self.server = server
        self.credential = credential
        self.session = session
    }

    /// Update the credential after login / pairing.
    func setCredential(_ credential: KimaCredential?) { self.credential = credential }

    /// Returns the HTTP auth header for the current credential, or nil when unauthenticated.
    /// JWT sessions → `("Authorization", "Bearer <token>")`.
    /// Device-link API-key sessions → `("x-api-key", "<key>")`.
    /// Used by `makeRequest` (DRY) and by `ImageCache` for cover-art requests.
    func authHeader() -> (field: String, value: String)? {
        guard let credential else { return nil }
        switch credential {
        case .jwt(let token): return ("Authorization", "Bearer \(token)")
        case .apiKey(let key): return ("x-api-key", key)
        }
    }

    // MARK: - Request plumbing

    // Internal (not private) so feature-area extensions in separate files (Library, Player, Search, …)
    // can build typed calls on top of these helpers without duplicating request logic.
    func get<T: Decodable>(_ path: String, query: [String: String] = [:], authed: Bool) async throws -> T {
        try await send(makeRequest(path, method: "GET", query: query, authed: authed))
    }

    func post<T: Decodable>(_ path: String, body: [String: String], authed: Bool) async throws -> T {
        var req = makeRequest(path, method: "POST", authed: authed)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }

    /// POST with no expected response body. Never throws; used for fire-and-forget endpoints
    /// (e.g. /auth/logout) where the caller does not need to decode a response.
    func postNoContent(_ path: String, authed: Bool) async {
        let req = makeRequest(path, method: "POST", authed: authed)
        _ = try? await session.data(for: req)
    }

    /// HTTP status of a 2-byte ranged GET (`Range: bytes=0-1`) on a track's stream, or nil when no HTTP answer came
    /// back (offline, TLS, 10 s timeout). The player asks only after a stream fails before it ever played:
    /// 404 means gone server-side (deleted row, `missingSince` flag, or out-of-root path).
    /// Auth is the normal header, never a URL token.
    func streamStatus(trackId: String) async -> Int? {
        var req = makeRequest("/library/tracks/\(trackId)/stream", method: "GET", authed: true)
        req.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        req.timeoutInterval = 10
        guard let result = try? await session.data(for: req),
              let http = result.1 as? HTTPURLResponse else { return nil }
        return http.statusCode
    }

    /// POST with a generic `Encodable` body — used when the payload is a structured type rather
    /// than a flat `[String: String]` dictionary (e.g. playback-state saves with nested objects).
    func postJSON<Body: Encodable, T: Decodable>(
        _ path: String, query: [String: String] = [:], body: Body, authed: Bool
    ) async throws -> T {
        try await send(jsonRequest(path, method: "POST", query: query, body: body, authed: authed))
    }

    /// POST with a generic `Encodable` body whose response is not read. Throws on 401 and any other
    /// non-2xx, like `deleteJSON`.
    func postJSONChecked<Body: Encodable>(_ path: String, body: Body, authed: Bool) async throws {
        try await sendChecked(jsonRequest(path, method: "POST", body: body, authed: authed))
    }

    /// POST with an `Encodable` body on the long-timeout session, for work that can outlast the default 60s timeout
    /// (Soulseek downloads block up to ~120s server-side). No 401 refresh-and-retry: this is a rare terminal call
    /// from an authenticated session, so an expired token surfaces as `.unauthorized` directly.
    func postJSONLongTimeout<Body: Encodable, T: Decodable>(_ path: String, body: Body, authed: Bool) async throws -> T {
        let req = try jsonRequest(path, method: "POST", body: body, authed: authed)
        let (data, http) = try await perform(req, on: longSession, refreshOn401: false)
        try check(data, http)
        return try decode(data)
    }

    /// PUT with a generic `Encodable` body. Routes 401 through single-flight refresh + retry
    /// via `send()`, identical to `postJSON`. Used by the Playlists feature (update).
    func putJSON<Body: Encodable, T: Decodable>(_ path: String, body: Body, authed: Bool) async throws -> T {
        try await send(jsonRequest(path, method: "PUT", body: body, authed: authed))
    }

    /// PATCH with a generic `Encodable` body. Routes 401 through single-flight refresh + retry
    /// via `send()`, identical to `postJSON`. Used by the Playlists feature (per-item move).
    func patchJSON<Body: Encodable, T: Decodable>(_ path: String, body: Body, authed: Bool) async throws -> T {
        try await send(jsonRequest(path, method: "PATCH", body: body, authed: authed))
    }

    /// DELETE that validates the full response status — throws on 401 AND all other non-2xx.
    /// Use this when the caller must surface errors to the user.
    func deleteChecked(_ path: String, authed: Bool) async throws {
        try await sendChecked(makeRequest(path, method: "DELETE", authed: authed))
    }

    /// DELETE with a JSON-encodable body. Routes 401 through single-flight refresh + retry.
    /// Used for endpoints that pass identifiers in the DELETE body (e.g. DELETE /discover/unlike).
    func deleteJSON<Body: Encodable>(_ path: String, body: Body, authed: Bool) async throws {
        try await sendChecked(jsonRequest(path, method: "DELETE", body: body, authed: authed))
    }

    // MARK: - Shared request path

    /// Decodes `data` as UTF-8 and clamps to 500 characters for use in `APIError.http`.
    /// Keeps diagnostic snippets short; avoids retaining large or sensitive payloads.
    private func errorBodySlice(_ data: Data) -> String? {
        String(data: data, encoding: .utf8).map { String($0.prefix(500)) }
    }

    private func makeRequest(_ path: String, method: String, query: [String: String] = [:], authed: Bool) -> URLRequest {
        var req = URLRequest(url: server.api(path, query: query))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Every request bypasses the cache. Belt-and-suspenders with the ephemeral session: credentialed responses
        // are never stored, even if the session is later swapped for a caching one.
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if authed, let (field, value) = authHeader() {
            req.setValue(value, forHTTPHeaderField: field)
        }
        return req
    }

    /// `makeRequest` plus a JSON-encoded body and the matching Content-Type.
    private func jsonRequest<Body: Encodable>(
        _ path: String, method: String, query: [String: String] = [:], body: Body, authed: Bool
    ) throws -> URLRequest {
        var req = makeRequest(path, method: method, query: query, authed: authed)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    /// One round-trip. A thrown transport error becomes `.network`; a non-HTTP answer becomes
    /// `.http(status: -1)`.
    private func transport(_ req: URLRequest, on s: URLSession) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await s.data(for: req)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(status: -1, body: nil)
        }
        return (data, http)
    }

    /// The single request path. On a 401 it refreshes the token (single-flight) and retries once; a second 401 is
    /// returned as-is, so it never loops. Refresh only happens for requests with an `Authorization` header and a
    /// stored refresh token: unauthenticated calls, `x-api-key` calls and `/auth/refresh` itself get their 401 back.
    private func perform(_ req: URLRequest, on s: URLSession? = nil, refreshOn401: Bool = true) async throws -> (Data, HTTPURLResponse) {
        let s = s ?? session
        let first = try await transport(req, on: s)
        guard first.1.statusCode == 401, refreshOn401,
              req.value(forHTTPHeaderField: "Authorization") != nil,
              KeychainStore.credential(KeychainStore.refreshToken, for: server) != nil else {
            return first
        }
        let newToken = try await singleFlightRefresh()
        var retryReq = req
        retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
        return try await transport(retryReq, on: s)
    }

    /// 2xx passes; 401 → `.unauthorized`; anything else → `.http` with a short body slice.
    private func check(_ data: Data, _ http: HTTPURLResponse) throws {
        switch http.statusCode {
        case 200..<300: return
        case 401: throw APIError.unauthorized
        default: throw APIError.http(status: http.statusCode, body: errorBodySlice(data))
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let path = req.url?.path ?? "?"
        let netStart = ContinuousClock.now
        let (data, http) = try await perform(req)
        let networkMs = apiDurationMs(since: netStart)
        try check(data, http)
        let decodeStart = ContinuousClock.now
        let result: T = try decode(data)
        let decodeMs = apiDurationMs(since: decodeStart)
        // One line per decoded call. This is the instrument that answers "why is tapping play
        // slower than the server takes" — split into the two halves that answer it: what the
        // server held us for, and what decoding its answer cost.
        apiTimingLog.notice(
            "api \(path, privacy: .public) status=\(http.statusCode) bytes=\(data.count) networkMs=\(networkMs) decodeMs=\(decodeMs)"
        )
        return result
    }

    /// `send` for calls with no response body to decode.
    private func sendChecked(_ req: URLRequest) async throws {
        let (data, http) = try await perform(req)
        try check(data, http)
    }

    /// Single-flight: concurrent 401s share one /auth/refresh round-trip and all receive the new token.
    /// On a real auth failure (401 from /auth/refresh) it wipes both stored tokens so the app presents Connect.
    /// It does not wipe on network errors, since the session may still be valid.
    private func singleFlightRefresh() async throws -> String {
        // Share an already-running refresh rather than firing N parallel /auth/refresh requests.
        if let existing = refreshTask {
            return try await existing.value
        }
        // Task { } inside an actor inherits actor isolation (Swift 6). The body runs on this
        // actor's executor after the outer call suspends at `await task.value` below, so
        // refreshAccessToken() can read/write actor-isolated state without reentrancy hazard.
        let task = Task { try await self.refreshAccessToken() }
        refreshTask = task
        do {
            let token = try await task.value
            refreshTask = nil
            return token
        } catch {
            refreshTask = nil
            if case APIError.unauthorized = error {
                // Refresh token is expired or revoked. Wipe both stored tokens; the .unauthorized
                // propagation causes the app auth gate to present the Connect screen.
                KeychainStore.set(nil, for: KeychainStore.accessToken)
                KeychainStore.set(nil, for: KeychainStore.refreshToken)
                // Tell AppEnvironment to drop its cached stream ticket too — otherwise it keeps
                // serving the now-wiped JWT (to cover-art auth / stream tickets) until teardown.
                // The observer just clears the cache; the next read reflects the wiped Keychain (nil).
                NotificationCenter.default.post(name: .kimaAccessTokenRotated, object: nil)
            }
            throw error
        }
    }
}
