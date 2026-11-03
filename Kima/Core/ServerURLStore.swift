import Foundation

/// Single accessor for the stored server address (`kima.serverURL` in UserDefaults). Every reader
/// goes through here so the DEBUG-only test override below is honoured everywhere — an override
/// that only some readers consult splits the app between two servers.
enum ServerURLStore {
    static let key = "kima.serverURL"

    #if DEBUG
    /// `-kima-fake-signed-in` sets this for its own process only, leaving the stored server
    /// intact so later launches still reach the real session.
    static var debugOverride: String?
    #endif

    /// The address this process talks to: the override when one is set, otherwise the stored value.
    static var current: String? {
        #if DEBUG
        if let debugOverride { return debugOverride }
        #endif
        return UserDefaults.standard.string(forKey: key)
    }

    /// Persisted address, ignoring the override: what the user actually has saved.
    static var stored: String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func setStored(_ urlString: String) {
        UserDefaults.standard.set(urlString, forKey: key)
    }
}
