import Foundation

/// What happens once credentials have succeeded anywhere: store the credential, best-effort
/// store the refresh token, drop every other server's stored login, persist the server address
/// — in this order, once. Every sign-in path ends here (password sign-in, account creation,
/// device-link); none performs any of these steps itself, and a fourth path adds one call, not
/// a copy-pasted ritual. The Keychain entry names for credentials live only in this file on the
/// write side; callers hand over what the server gave them, not where it goes. A *login* is
/// credentials plus their address — establish turns the pair into one.
///
/// The order is the invariant: the access credential is saved before anything else can depend
/// on it existing, and its failure stops everything (no refresh write, no erase, no address —
/// the caller says so in its own words). Other servers' logins are erased before this one is
/// remembered as *the* server, and the address is persisted last: a crash between the two
/// leaves a login that resumes nowhere, which the Connect screen handles; the reverse — an
/// address pointing at a half-written credential — would not.
enum LoginRitual {
    /// The credential a sign-in path just received from its server.
    enum Credential {
        case jwt(accessToken: String, refreshToken: String?)
        case apiKey(String)

        /// The refresh token to best-effort store alongside the primary credential — nil for
        /// an API key, where the write doubles as the delete of any stale token.
        var refreshToken: String? {
            if case .jwt(_, let refreshToken) = self { return refreshToken }
            return nil
        }

        /// The Keychain entries this login just wrote; every other credential entry goes.
        fileprivate var keepEntries: Set<String> {
            switch self {
            case .jwt: return [KeychainStore.accessToken, KeychainStore.refreshToken]
            case .apiKey: return [KeychainStore.apiKey]
            }
        }
    }

    /// Performs the ritual against `server`. Returns false when the primary credential could
    /// not be written to the Keychain — nothing else was touched. The four sinks mirror the
    /// four steps (tests watch them); production runs them on the real stores, and a failing
    /// refresh write is ignored: servers (and accounts) without one still sign in.
    @discardableResult
    static func establish(
        _ credential: Credential, at server: KimaServer,
        saveCredential: (Credential, KimaServer) -> Bool = writePrimaryToKeychain,
        saveRefreshToken: (String?, KimaServer) -> Bool = writeRefreshToKeychain,
        eraseOtherLogins: (Credential, KimaServer) -> Void = clearOtherCredentials,
        rememberServer: (KimaServer) -> Void = persistServerURL
    ) -> Bool {
        guard saveCredential(credential, server) else { return false }
        _ = saveRefreshToken(credential.refreshToken, server)   // best-effort by contract
        eraseOtherLogins(credential, server)
        rememberServer(server)
        return true
    }

    /// Store the primary credential — the JWT or the device's API key — bound to the server
    /// that issued it. One Keychain item carries both, so no crash can pair a token with
    /// another server's address.
    private static func writePrimaryToKeychain(_ credential: Credential, _ server: KimaServer) -> Bool {
        switch credential {
        case .jwt(let accessToken, _):
            return KeychainStore.setCredential(accessToken, for: KeychainStore.accessToken, server: server)
        case .apiKey(let key):
            return KeychainStore.setCredential(key, for: KeychainStore.apiKey, server: server)
        }
    }

    /// Best-effort refresh-token write; nil deletes any stale one (e.g. from a previous server).
    private static func writeRefreshToKeychain(_ refreshToken: String?, _ server: KimaServer) -> Bool {
        KeychainStore.setCredential(refreshToken, for: KeychainStore.refreshToken, server: server)
    }

    /// Drop any other stored login — e.g. another server's API key, which would otherwise win
    /// over this credential — keeping exactly the entries just written.
    private static func clearOtherCredentials(_ credential: Credential, _ server: KimaServer) {
        KeychainStore.clearCredentials(except: credential.keepEntries)
    }

    private static func persistServerURL(_ server: KimaServer) {
        ServerURLStore.setStored(server.baseURL.absoluteString)
    }
}
