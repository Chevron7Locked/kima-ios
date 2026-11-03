@testable import Kima

/// The simulator's real login, saved before a test writes the Keychain and put back after it,
/// with each credential still bound to its server so the simulator stays signed in.
struct KeychainLoginSnapshot {
    private let items: [(key: String, stored: KeychainStore.StoredCredential?)]

    init() {
        items = KeychainStore.credentialKeys.map { ($0, KeychainStore.storedCredential($0)) }
    }

    func restore() {
        for item in items { KeychainStore.restore(item.stored, for: item.key) }
    }
}
