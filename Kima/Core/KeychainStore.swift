import Foundation
import Security

/// A tiny Keychain wrapper for Kima secrets (JWT / refresh token / device-link API key).
/// The server URL itself is not secret and lives in UserDefaults; credentials live here, each
/// item carrying the server it was issued by (`setCredential`), and are read only for that server.
enum KeychainStore {
    private static let service = "com.chevron7locked.kima"

    // Well-known keys.
    static let apiKey = "kima.apiKey"
    static let accessToken = "kima.accessToken"
    static let refreshToken = "kima.refreshToken"

    /// The login credentials. Sign-out and an expired session delete only these, so a trusted
    /// self-signed certificate (`certificatePinKey(host:)`) outlives them.
    static let credentialKeys = [apiKey, accessToken, refreshToken]

    /// Account holding the pinned public key of a self-signed certificate for `host`.
    static func certificatePinKey(host: String) -> String { "kima.certpin.\(host)" }

    /// Store (or, with nil, delete) a secret. Returns false if the Keychain write failed
    /// (so callers can surface the problem instead of silently losing a credential).
    @discardableResult
    static func set(_ value: String?, for key: String) -> Bool {
        write(value, for: key, server: nil)
    }

    /// Store (or, with nil, delete) a login credential together with the server it belongs to, in
    /// one Keychain item, so no crash between two writes can pair it with another server's address.
    @discardableResult
    static func setCredential(_ value: String?, for key: String, server: KimaServer) -> Bool {
        write(value, for: key, server: serverID(server))
    }

    private static func write(_ value: String?, for key: String, server: String?) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return true } // nil ⇒ delete
        var add = base
        add[kSecValueData as String] = data
        // kSecAttrGeneric is the item's app-defined attribute: here, the credential's server.
        if let server { add[kSecAttrGeneric as String] = Data(server.utf8) }
        // AfterFirstUnlockThisDeviceOnly: items are readable after the first unlock post-boot,
        // are excluded from iCloud Keychain sync, and cannot be extracted via iTunes/local
        // backup or device migration. Required for background URLSession
        // token-refresh while the screen is locked.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// One stored login credential: the secret and the server it is bound to (nil when unbound).
    struct StoredCredential: Equatable {
        let value: String
        let server: String?
    }

    /// The credential under `key` with its server binding; nil when absent or unreadable.
    static func storedCredential(_ key: String) -> StoredCredential? {
        readWithServer(key).map { StoredCredential(value: $0.value, server: $0.server) }
    }

    /// Writes `stored` back under `key` with the same server binding (nil deletes the item).
    @discardableResult
    static func restore(_ stored: StoredCredential?, for key: String) -> Bool {
        write(stored?.value, for: key, server: stored?.server)
    }

    /// The server a credential is saved for: the address exactly as the app stores it.
    static func serverID(_ server: KimaServer) -> String { server.baseURL.absoluteString }

    /// A login credential saved for `server`; nil when absent, unreadable, saved for another
    /// server, or saved with no server at all (see `bindUnboundCredentials`).
    static func credential(_ key: String, for server: KimaServer) -> String? {
        guard let item = readWithServer(key), item.server == serverID(server) else { return nil }
        return item.value
    }

    /// Credentials written before they carried a server have none. On the first launch that can,
    /// each is bound to `server`, the address stored next to it (the pairing the app used then), in
    /// place without rewriting the secret. After one complete pass it never runs again, so an
    /// unbound item that appears later is never sent anywhere.
    static func bindUnboundCredentials(to server: KimaServer, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: bindingDoneKey) else { return }
        var complete = true
        for key in credentialKeys {
            if case .failed = read(key) { complete = false; continue }   // unreadable now: retry next launch
            guard let item = readWithServer(key), item.server == nil else { continue }
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
            ]
            let update: [String: Any] = [kSecAttrGeneric as String: Data(serverID(server).utf8)]
            if SecItemUpdate(query as CFDictionary, update as CFDictionary) != errSecSuccess { complete = false }
        }
        if complete { defaults.set(true, forKey: bindingDoneKey) }
    }

    private static let bindingDoneKey = "kima.credentialsBoundToServer"

    /// One item's secret and its server (nil when it has none); nil when absent or unreadable.
    private static func readWithServer(_ key: String) -> (value: String, server: String?)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any],
              let data = attributes[kSecValueData as String] as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        let server = (attributes[kSecAttrGeneric as String] as? Data).flatMap { String(data: $0, encoding: .utf8) }
        return (value, server?.isEmpty == true ? nil : server)
    }

    /// Read a secret, or nil if absent.
    /// What a Keychain read found. `failed` is any error other than "no such item" (locked
    /// Keychain, missing entitlement, unreadable data): a security check must treat it as unknown,
    /// never as "nothing stored".
    enum ReadResult: Equatable {
        case found(String)
        case absent
        case failed(OSStatus)
    }

    /// Read a secret, telling "not stored" apart from a Keychain error. `copyMatching` is
    /// `SecItemCopyMatching`; tests pass a stand-in to produce the error statuses.
    static func read(
        _ key: String,
        copyMatching: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemCopyMatching
    ) -> ReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = copyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
                return .failed(errSecDecode)
            }
            return .found(string)
        case errSecItemNotFound:
            return .absent
        default:
            return .failed(status)
        }
    }

    /// Delete the login credentials (except `keep`) and nothing else. True when each was deleted or
    /// already absent. A new sign-in passes the keys it just wrote, so no other server's login stays.
    @discardableResult
    static func clearCredentials(except keep: Set<String> = []) -> Bool {
        credentialKeys.filter { !keep.contains($0) }.map(delete).allSatisfy { $0 }
    }

    /// Forget the trusted certificate for `host`; the next connection pins the key the server presents.
    @discardableResult
    static func forgetTrustedCertificate(host: String) -> Bool {
        delete(certificatePinKey(host: host))
    }

    /// Delete one account under the Kima service, synced or not. True when deleted or already absent.
    private static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            // Query-only: matches synced and unsynced copies alike (see clearAll()).
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Remove every secret this app has stored under the Kima service, regardless of key name,
    /// certificate pins included. Returns true if all items were deleted or were already absent.
    /// Used only by the first-install wipe below.
    @discardableResult
    static func clearAll() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            // SynchronizableAny so the wipe matches both synced and non-synced items
            // (a delete query without this key matches only non-synchronizable items).
            // This is a query-only value — never add it to set()'s base dict (it's reused
            // for SecItemAdd, where SynchronizableAny is invalid).
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// iOS does NOT clear Keychain items on uninstall, so a reinstall on a re-used device would inherit the previous
    /// owner's credentials, including the permanent API key. A UserDefaults sentinel (cleared on uninstall) detects a
    /// fresh install, and stale Keychain entries are purged before any auth check runs.
    static func wipeStaleCredentialsOnFirstInstall() {
        let sentinelKey = "kima.keychainInitialized"
        guard !UserDefaults.standard.bool(forKey: sentinelKey) else { return }
        // Mark initialized only once the wipe succeeds. clearAll() also returns true on errSecItemNotFound (a real
        // fresh install). If it fails (Keychain transiently unavailable), leave the sentinel unset so the wipe
        // retries next launch instead of keeping stale credentials.
        if clearAll() {
            UserDefaults.standard.set(true, forKey: sentinelKey)
        }
    }
}
