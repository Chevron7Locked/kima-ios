import Foundation

/// The one module that owns the self-signed-certificate story end to end: it decides whether a
/// presented certificate is acceptable (trust-on-first-use public-key pinning), keeps pin-storage
/// semantics where a failed read or write is never taken for "no pin", guards generations so a stale
/// challenge cannot re-alert after the user's newer decision, and owns the reported-change state the
/// UI binds (`changes`). The URLSession delegate is a thin adapter over `handle`, which lets the
/// whole story be tested with synthetic challenges — no TLS required. Publicly-trusted certificates
/// are never pinned; they keep full CA-chain validation.
final class ServerTrust: @unchecked Sendable {
    /// Process-wide instance, deliberately: pins are per-host and shared by every session (API, event
    /// stream, cover art), and the generation guard only protects against stale reports if exactly one
    /// module sees all of them. Unit tests construct their own against fake pin storage.
    static let shared = ServerTrust()

    /// A presented certificate described by values instead of a `SecTrust` — what the delegate adapter
    /// extracts from a real challenge, and what a test can synthesize. `systemValidated` is the CA-chain
    /// verdict; `publicKeyPin` is nil when the leaf's key could not be extracted; `namesHost` is whether
    /// the leaf names the host being connected to (a pin proves a key, not that the key serves this host).
    struct PresentedCertificate {
        let host: String
        let systemValidated: Bool
        let publicKeyPin: String?
        let namesHost: Bool
    }

    /// The one answer to one challenge. `useCredential` means trust this exact connection;
    /// `block` cancels it; `defaultHandling` leaves the decision to the system (publicly-trusted certs).
    enum Answer: Equatable {
        case defaultHandling
        case useCredential
        case block
    }

    /// The reported changes the certificate-alert UI binds. One observable for every surface, wired so
    /// its `trust(host:)` answers through this module's storage core.
    let changes: ServerTrustState

    private let keys: TrustedKeys

    init(pins: CertificatePins = KeychainCertificatePins()) {
        let keys = TrustedKeys(pins: pins)
        self.keys = keys
        self.changes = ServerTrustState(onTrust: { keys.trustNew(host: $0) })
    }

    /// The thin URLSession adapter every Kima session rides on — the session factory wires it.
    /// Computed because a delegate holds its module and URLSession retains its delegate; all state
    /// lives in the module, so per-session adapters are interchangeable.
    var delegate: ServerTrustDelegate { ServerTrustDelegate(trust: self) }

    /// What to do with a self-signed certificate, given what pin storage holds for its host.
    enum PinDecision: Equatable {
        case accept                          // stored pin and host name both match
        case pinFirstUse                     // nothing stored: store this key, then accept
        case reportChange(keyChanged: Bool)  // reject and alert: the key, or only the name, changed
        case refuse                          // reject without an alert
    }

    /// A pin proves the same key, not that the key serves this host, so the leaf must also name the
    /// host. A storage read error is not "no pin": pinning then would swap the stored key for whatever
    /// this server presents, so it refuses and writes nothing. A first-contact MITM can still pin its
    /// own key (inherent to trust-on-first-use); the change alert catches it after.
    static func decide(stored: KeychainStore.ReadResult, presented pin: String, hostMatches: Bool) -> PinDecision {
        switch stored {
        case .found(let storedPin):
            if storedPin == pin, hostMatches { return .accept }
            return .reportChange(keyChanged: storedPin != pin)
        case .absent:
            return hostMatches ? .pinFirstUse : .refuse
        case .failed:
            return .refuse
        }
    }

    /// Answer one presented certificate, exactly once on every path. First-use pins are written before
    /// accepting (a failed write fails closed — accepting anyway would re-pin on every connection); a
    /// change is blocked and reported to `changes`, unless the user has since trusted a new certificate
    /// for this host, which makes this report stale.
    func handle(_ presented: PresentedCertificate, completion: @escaping (Answer) -> Void) {
        // A certificate the system itself validates is publicly trusted — no TOFU layer involved.
        guard !presented.systemValidated else {
            completion(.defaultHandling)
            return
        }
        // Chain or key extraction failed — fail safe; reject the connection.
        guard let pin = presented.publicKeyPin else {
            completion(.block)
            return
        }

        let judgement = keys.judge(pin: pin, host: presented.host, namesHost: presented.namesHost)

        if case .reportChange(let keyChanged) = judgement.decision {
            let keys = self.keys, changes = self.changes
            Task { @MainActor in
                guard keys.isCurrent(judgement.generation) else { return }
                changes.report(host: presented.host, keyChanged: keyChanged)
            }
        }
        completion(judgement.accepted ? .useCredential : .block)
    }
}

/// The module's shared mutable core: the pin storage and the generation counter, serialized under one
/// lock. Both halves of the module work on it — challenge handling reads, decides and pins first use
/// atomically, while the user's "trust the new certificate" answer forgets and bumps — so a challenge
/// can observe that its report went stale against a decision made after it started.
final class TrustedKeys: @unchecked Sendable {
    private let pins: CertificatePins

    /// Serialises the TOFU pin get-check-set so two concurrent challenges to the same new host
    /// (e.g. the API + SSE sessions connecting at launch) can't both read a missing pin and race
    /// the write. It also guards `generation`, which is what makes the `@unchecked Sendable`
    /// conformance sound.
    private let lock = NSLock()

    /// Bumped each time the user trusts a new certificate. A challenge that read the old generation
    /// before that (a connection already in flight) doesn't raise the alert again.
    private var generation = 0

    init(pins: CertificatePins) { self.pins = pins }

    /// The verdict of one challenge plus the generation it was judged against.
    struct Judgement {
        let decision: ServerTrust.PinDecision
        /// Whether the connection may proceed — a first-use pin only accepts if the write succeeded.
        let accepted: Bool
        let generation: Int
    }

    /// The TOFU critical section under one lock: read the stored pin, decide, and on first use store
    /// the presented key (a failed write leaves `accepted` false — fail closed).
    func judge(pin: String, host: String, namesHost: Bool) -> Judgement {
        lock.lock()
        defer { lock.unlock() }
        let decision = ServerTrust.decide(stored: pins.pin(for: host), presented: pin, hostMatches: namesHost)
        var accepted = false
        switch decision {
        case .accept:
            accepted = true
        case .pinFirstUse:
            accepted = pins.setPin(pin, for: host)
        case .reportChange, .refuse:
            break
        }
        return Judgement(decision: decision, accepted: accepted, generation: generation)
    }

    /// "trust the new certificate": forgets `host`'s pin under the same lock as the TOFU check, so the
    /// next connection pins the key the server presents, and bumps the generation so challenges that
    /// read the old pin (connections already in flight) go quiet.
    func trustNew(host: String) {
        lock.lock()
        defer { lock.unlock() }
        pins.forgetPin(for: host)
        generation += 1
    }

    /// Whether a challenge judged at `generation` still speaks for the user's current decision.
    func isCurrent(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == self.generation
    }
}

/// Where the module's public-key pins live. The tri-state read is the whole contract: `absent` (first
/// use may pin) must never be confused with a failed read (refuse, write nothing).
protocol CertificatePins {
    func pin(for host: String) -> KeychainStore.ReadResult
    @discardableResult
    func setPin(_ pin: String, for host: String) -> Bool
    func forgetPin(for host: String)
}

/// Production storage: the Keychain entry `kima.certpin.<host>`, written on first connection and
/// forgotten when the user answers "trust the new certificate".
struct KeychainCertificatePins: CertificatePins {
    func pin(for host: String) -> KeychainStore.ReadResult {
        KeychainStore.read(KeychainStore.certificatePinKey(host: host))
    }

    @discardableResult
    func setPin(_ pin: String, for host: String) -> Bool {
        KeychainStore.set(pin, for: KeychainStore.certificatePinKey(host: host))
    }

    func forgetPin(for host: String) {
        KeychainStore.forgetTrustedCertificate(host: host)
    }
}
