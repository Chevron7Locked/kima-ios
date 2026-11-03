import Foundation
import Security
import CryptoKit

/// URLSession delegate implementing Trust-On-First-Use public-key pinning for self-signed certificates. The leaf
/// key's SHA-256 fingerprint is stored in Keychain (`kima.certpin.<host>`) on first connection; a later change
/// rejects the connection and reports the host to `ServerTrustState.shared` so the UI can alert. Publicly-trusted
/// certs are never pinned and keep full CA-chain validation.
final class ServerTrustCoordinator: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = ServerTrustCoordinator()

    private override init() { super.init() }

    /// Serialises the TOFU pin get-check-set so two concurrent challenges to the same new
    /// host (e.g. the API + SSE sessions connecting at launch) can't both read a missing pin
    /// and race the write. It also guards `trustGeneration`, the coordinator's only other
    /// mutable state, which is what makes the `@unchecked Sendable` conformance sound.
    private let pinLock = NSLock()

    /// Bumped each time the user trusts a new certificate. A challenge that read the old pin
    /// before that (a connection already in flight) doesn't raise the alert again.
    private var trustGeneration = 0

    /// "trust the new certificate": forgets `host`'s pin under the same lock as the TOFU check, so
    /// the next connection pins the key the server presents.
    func trustNewCertificate(host: String) {
        pinLock.lock()
        defer { pinLock.unlock() }
        KeychainStore.forgetTrustedCertificate(host: host)
        trustGeneration += 1
    }

    private func isCurrentTrust(_ generation: Int) -> Bool {
        pinLock.lock()
        defer { pinLock.unlock() }
        return generation == trustGeneration
    }

    /// What to do with a self-signed certificate, given what the Keychain holds for its host.
    enum PinDecision: Equatable {
        case accept                          // stored pin and host name both match
        case pinFirstUse                     // nothing stored: store this key, then accept
        case reportChange(keyChanged: Bool)  // reject and alert: the key, or only the name, changed
        case refuse                          // reject without an alert
    }

    /// A pin proves the same key, not that the key serves this host, so the leaf must also name the
    /// host. A Keychain read error is not "no pin": pinning then would swap the stored key for
    /// whatever this server presents, so it refuses and writes nothing. A first-contact MITM can
    /// still pin its own key (inherent to trust-on-first-use); the change alert catches it after.
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

    // MARK: - URLSessionDelegate

    /// Called for every server-trust authentication challenge on sessions using this delegate.
    /// The completion handler is guaranteed to be called exactly once on every code path.
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Non-server-trust challenges (e.g. client certs) go through default handling.
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 1. Try standard CA-chain validation first.
        //    If the system accepts the cert this is publicly-trusted (Let's Encrypt, Caddy,
        //    Tailscale HTTPS, …) — let the system enforce it without any TOFU layer.
        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 2. System validation failed → self-signed / private CA path.
        //    Compute a public-key pin: SHA-256 of the leaf certificate's raw public key
        //    (DER-encoded). Pinning the key (not the cert) means the pin survives cert
        //    renewal as long as the same key pair is reused — common for self-signed servers.
        guard let pinHex = leafPublicKeyPin(from: trust) else {
            // Chain or key extraction failed — fail safe; reject the connection.
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let host = challenge.protectionSpace.host
        let keychainKey = KeychainStore.certificatePinKey(host: host)

        // Serialise the pin read/compare/write so concurrent same-host challenges can't race.
        // Decide the disposition under the lock; invoke the completion handler once, outside it.
        pinLock.lock()
        let generation = trustGeneration
        let decision = Self.decide(
            stored: KeychainStore.read(keychainKey),
            presented: pinHex,
            hostMatches: leaf(host: host, matches: trust)
        )
        var accepted = false
        var changeReport: Bool?   // keyChanged, when the alert should show
        switch decision {
        case .accept:
            accepted = true
        case .pinFirstUse:
            // A failed write fails closed: accepting anyway would re-pin on every connection.
            accepted = KeychainStore.set(pinHex, for: keychainKey)
        case .reportChange(let keyChanged):
            changeReport = keyChanged
        case .refuse:
            break
        }
        pinLock.unlock()
        let disposition: URLSession.AuthChallengeDisposition = accepted ? .useCredential : .cancelAuthenticationChallenge
        let credential = accepted ? URLCredential(trust: trust) : nil

        if let keyChanged = changeReport {
            Task { @MainActor in
                guard self.isCurrentTrust(generation) else { return }
                ServerTrustState.shared.report(host: host, keyChanged: keyChanged)
            }
        }
        completionHandler(disposition, credential)
    }

    /// Strips auth credentials from redirects that downgrade https to http or change host. iOS would otherwise
    /// forward `Authorization` on a same-host downgrade and leak the bearer token in plaintext. Safe redirects pass
    /// through unchanged; for the others the redirect still loads, only without the credential.
    /// Shared by the API, SSE, and image sessions. Stateless.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let originalURL = task.originalRequest?.url,
              let newURL = request.url else {
            // Cannot evaluate the boundary — follow without modification. No auth headers
            // are being added here, so forwarding is safe.
            completionHandler(request)
            return
        }

        let schemeDowngrade = originalURL.scheme?.lowercased() == "https"
                           && newURL.scheme?.lowercased() == "http"
        let hostChanged = originalURL.host?.lowercased() != newURL.host?.lowercased()

        guard schemeDowngrade || hostChanged else {
            // Safe redirect: same host, no scheme downgrade — forward unchanged.
            completionHandler(request)
            return
        }

        // Strip auth credentials before following the cross-boundary redirect.
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        stripped.setValue(nil, forHTTPHeaderField: "x-api-key")
        completionHandler(stripped)
    }

    // MARK: - Private

    /// True when the leaf certificate names `host` (see `CertificateHostNames`).
    private func leaf(host: String, matches trust: SecTrust) -> Bool {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leafCert = chain.first else { return false }
        return CertificateHostNames.certificate(leafCert, names: host)
    }

    /// Returns a lowercase hex SHA-256 fingerprint of the leaf certificate's raw public key,
    /// or nil if the chain or key cannot be extracted.
    private func leafPublicKeyPin(from trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            return nil
        }
        guard let key = SecCertificateCopyKey(leaf) else { return nil }
        var err: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(key, &err) as Data? else {
            return nil
        }
        let digest = SHA256.hash(data: keyData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
