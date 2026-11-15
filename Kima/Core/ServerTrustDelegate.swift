import Foundation
import Security
import CryptoKit

/// Thin URLSession adapter over the ServerTrust module: it extracts what a real server-trust challenge
/// presents into the values the module reasons about, hands them over, and translates the single answer
/// back into URLSession's disposition. No trust decision lives here — that is what lets the whole cert
/// story be unit-tested with synthetic challenges against the module. The completion handler is called
/// exactly once on every path: two guard returns plus one call from the module's completion.
///
/// Also carries the redirect hygiene shared by the API, SSE and image sessions (credentials are
/// stripped from redirects that cross a security boundary). Stateless; each session retains its own,
/// all state lives in the module behind `trust`.
final class ServerTrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let trust: ServerTrust

    init(trust: ServerTrust) { self.trust = trust }

    /// Called for every server-trust authentication challenge on sessions using this delegate.
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Non-server-trust challenges (e.g. client certs) go through default handling.
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let secTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        let presented = ServerTrust.PresentedCertificate(
            host: host,
            // True when the system itself validates the chain — publicly trusted (Let's Encrypt, Caddy,
            // Tailscale HTTPS, …); the module lets the system enforce those without any TOFU layer.
            systemValidated: SecTrustEvaluateWithError(secTrust, nil),
            publicKeyPin: leafPublicKeyPin(from: secTrust),
            namesHost: leaf(host: host, matches: secTrust)
        )
        trust.handle(presented) { answer in
            switch answer {
            case .defaultHandling:
                completionHandler(.performDefaultHandling, nil)
            case .useCredential:
                completionHandler(.useCredential, URLCredential(trust: secTrust))
            case .block:
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }

    /// Strips auth credentials from redirects that downgrade https to http or change host. iOS would
    /// otherwise forward `Authorization` on a same-host downgrade and leak the bearer token in plaintext.
    /// Safe redirects pass through unchanged; for the others the redirect still loads, only without the
    /// credential. Shared by the API, SSE, and image sessions. Stateless.
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

    // MARK: - Extraction

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
