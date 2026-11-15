import Foundation
@testable import Kima

/// In-memory `CertificatePins` for synthetic-challenge tests. The tri-state of pin storage —
/// a stored value, nothing stored, an unreadable store — is synthesized per host because a real
/// Keychain won't produce a read error on demand, and the same reason applies to write failure.
/// Every operation is recorded so a test can assert what was written when: a failed pin attempt
/// must never be confused with no pin at all, in the module or in its tests.
final class FakeCertificatePins: CertificatePins {
    /// What a read for one host answers. Absent from the dictionary means nothing stored.
    var results: [String: KeychainStore.ReadResult] = [:]

    /// When false every write fails and stores nothing — the module must fail closed.
    var writeSucceeds = true

    private(set) var readHosts: [String] = []
    private(set) var setCalls: [(host: String, pin: String)] = []
    private(set) var forgetCalls: [String] = []

    func pin(for host: String) -> KeychainStore.ReadResult {
        readHosts.append(host)
        return results[host] ?? .absent
    }

    @discardableResult
    func setPin(_ pin: String, for host: String) -> Bool {
        setCalls.append((host, pin))
        guard writeSucceeds else { return false }
        results[host] = .found(pin)
        return true
    }

    func forgetPin(for host: String) {
        forgetCalls.append(host)
        results[host] = nil
    }
}
