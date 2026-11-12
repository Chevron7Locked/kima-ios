import Foundation
@testable import Kima

/// The simulator's real login, saved before a test writes the Keychain and put back after it:
/// each credential still bound to its server, plus the stored server address the credentials
/// belong to (a login is both — restoring one without the other can point a kept credential at
/// the wrong server). Suites that seed an address get its restore for free; suites that never
/// touch it get a no-op write-back.
struct KeychainLoginSnapshot {
    private let items: [(key: String, stored: KeychainStore.StoredCredential?)]
    private let address: String?

    init() {
        items = KeychainStore.credentialKeys.map { ($0, KeychainStore.storedCredential($0)) }
        address = UserDefaults.standard.string(forKey: ServerURLStore.key)
    }

    func restore() {
        for item in items { KeychainStore.restore(item.stored, for: item.key) }
        UserDefaults.standard.set(address, forKey: ServerURLStore.key)
    }
}
