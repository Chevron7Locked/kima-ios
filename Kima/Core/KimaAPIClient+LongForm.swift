import Foundation

// MARK: - Auth probe + refresh (mid-stream 401 recovery)
// Used by the long-form playback engine: when an AVPlayer item fails, probe /auth/me to tell an expired token
// from a transport error, then refresh and rebuild the asset.

extension KimaAPIClient {

    /// `true` when the stored JWT is still valid; `false` on 401. Network blips return `true`
    /// (treated as non-auth failures so we don't falsely invalidate the session).
    func probeAuthMe() async -> Bool {
        struct MeProbe: Decodable {}
        do {
            let _: MeProbe = try await get("/auth/me", authed: true)
            return true
        } catch APIError.unauthorized {
            return false
        } catch {
            return true
        }
    }

    // MARK: - Stream ticket (short-lived scoped token for ?token= stream URLs)

    /// Short-lived stream ticket for `?token=` URLs, cached until half its lifetime. On a 404 (server without the
    /// ticket endpoint) returns the login JWT, the only stream credential that server accepts; on any other
    /// failure returns nil, and callers must not substitute the login JWT. Single-flight, like `refreshTask`.
    /// Seconds until the cached ticket reaches its renewal point; nil when nothing is cached.
    /// Exposed so the warm-keeper can sleep exactly as long as a minted ticket stays valid.
    var ticketRenewalDelay: TimeInterval? {
        guard let cached = cachedStreamTicket else { return nil }
        return max(0, cached.renewsAt.timeIntervalSinceNow)
    }

    func streamTicket() async -> String? {
        struct StreamTicketResponse: Decodable {
            let ticket: String
            let expiresIn: Int
        }

        // Cache hit: not yet at the proactive renewal point (refresh at TTL/2 rather than
        // only in the last 60 s, so a stream started 3h59m into a cached ticket can't be
        // scheduled to die mid-song when the server enforces expiry on the live connection).
        if let cached = cachedStreamTicket, Date.now < cached.renewsAt {
            return cached.ticket
        }
        // Single-flight: share an already-in-flight Task (mirrors `refreshTask` pattern).
        if let existing = ticketTask {
            return await existing.value
        }
        // Task { } inside an actor inherits actor isolation (Swift 6). Reads/writes to
        // actor-isolated state (cachedStreamTicket, post) is safe.
        let task = Task<String?, Never> {
            do {
                // `post` (internal helper, empty body) carries the credential header and the
                // 401→/auth/refresh→retry, same as every other authed call.
                let response: StreamTicketResponse = try await post("/auth/stream-ticket", body: [:], authed: true)
                let expiry = Date.now.addingTimeInterval(TimeInterval(response.expiresIn))
                // Proactive renewal at TTL/2 (never later than the absolute 60 s pre-expiry
                // deadline for pathological tiny TTLs).
                let renewsAt = min(
                    Date.now.addingTimeInterval(TimeInterval(response.expiresIn) / 2),
                    expiry.addingTimeInterval(-60)
                )
                self.cachedStreamTicket = (ticket: response.ticket, expiry: expiry, renewsAt: renewsAt)
                return response.ticket
            } catch APIError.http(let status, _) where status == 404 {
                // Server predates stream tickets: the login JWT is the only stream credential it accepts.
                return KeychainStore.credential(KeychainStore.accessToken, for: server)
            } catch {
                return nil   // never fall back to the login JWT: it would sit in proxy logs as an all-scope credential
            }
        }
        ticketTask = task
        let result = await task.value
        ticketTask = nil
        return result
    }

    /// Clears the cached stream ticket so the next `streamTicket()` call fetches a fresh one.
    /// Called before rebuilding a stream after a 401 — a 4-hour ticket expiring mid-session
    /// is the common re-auth trigger, so the rebuild must not reuse the stale ticket.
    func invalidateStreamTicket() {
        cachedStreamTicket = nil
    }

    // MARK: - Token refresh

    /// POST /api/auth/refresh — exchange the stored refresh token for a fresh access token.
    /// The server rotates the refresh token on every use; both new tokens are persisted here, the single place
    /// token rotation happens. Throws `.unauthorized` if none is stored or the server rejects it, and `.network` on
    /// transport failure, where callers must NOT clear tokens (the session may still be valid).
    func refreshAccessToken() async throws -> String {
        guard let storedRefresh = KeychainStore.credential(KeychainStore.refreshToken, for: server) else {
            throw APIError.unauthorized
        }
        struct RefreshBody: Encodable { let refreshToken: String }
        struct RefreshResponse: Decodable { let token: String; let refreshToken: String }
        let r: RefreshResponse = try await postJSON(
            "/auth/refresh", body: RefreshBody(refreshToken: storedRefresh), authed: false
        )
        // Persist both tokens. Storing only the access token silently breaks the NEXT refresh
        // because the server has already invalidated the old refresh token.
        guard KeychainStore.setCredential(r.token, for: KeychainStore.accessToken, server: server) else {
            throw APIError.network(NSError(domain: "KeychainStore", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to persist access token"]))
        }
        guard KeychainStore.setCredential(r.refreshToken, for: KeychainStore.refreshToken, server: server) else {
            throw APIError.network(NSError(domain: "KeychainStore", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to persist refresh token"]))
        }
        // Update the in-memory credential so subsequent requests on this client instance
        // immediately use the new token without re-reading the Keychain.
        setCredential(.jwt(r.token))
        // Notify AppEnvironment to drop the cached stream ticket.
        NotificationCenter.default.post(name: .kimaAccessTokenRotated, object: nil)
        return r.token
    }
}
