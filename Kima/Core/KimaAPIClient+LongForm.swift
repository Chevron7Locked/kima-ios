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
        // Notify the session's StreamSource (and any other holder) so cached stream tickets,
        // which were minted against the old token, are dropped.
        NotificationCenter.default.post(name: .kimaAccessTokenRotated, object: nil)
        return r.token
    }
}
