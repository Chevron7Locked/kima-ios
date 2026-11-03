import SwiftUI
import Observation

/// Top-level auth state for the whole app. Owns the launch "do we have a live session?" decision
/// and the sign-out path. Server URL lives in UserDefaults ("kima.serverURL"); the credential in
/// the Keychain, saved for that server (KimaCredential.fromKeychain(for:), apiKey-precedence).
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case launching                 // validating a remembered credential on cold start
        case authenticated(host: String)
        /// Stored session, but the server can't be reached, or answered with an error
        /// (`serverError` says which) — the gate offers retry and a new address.
        case unreachable(host: String, serverError: String? = nil)
        case unauthenticated
    }

    private(set) var phase: Phase = .launching
    private var isSigningOut = false

    /// Display host that preserves a non-default port (self-hosted Kima often runs on one).
    nonisolated static func displayHost(for url: URL, fallback: String) -> String {
        guard let host = url.host() else { return fallback }
        guard let port = url.port else { return host }
        return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"   // IPv6 bracketed, as in a URL
    }

    /// Cold-launch resume. If a stored server + credential exist, validate via GET /api/auth/me.
    func resume() async {
        #if DEBUG
        // Screenshot/verify hook: seed server + JWT from launch args so sweeps run
        // against a testbed without driving the sign-in form. App-process writes →
        // keychain lands in the app's own keychain (simctl-spawn writes would not).
        //   -kima-server http://host:3030 -kima-jwt <token>
        if let i = CommandLine.arguments.firstIndex(of: "-kima-server"), i + 1 < CommandLine.arguments.count {
            ServerURLStore.setStored(CommandLine.arguments[i + 1])
        }
        if let j = CommandLine.arguments.firstIndex(of: "-kima-jwt"), j + 1 < CommandLine.arguments.count,
           let seeded = ServerURLStore.current.flatMap(URL.init(string:)) {
            let server = KimaServer(baseURL: seeded)
            KeychainStore.setCredential(CommandLine.arguments[j + 1], for: KeychainStore.accessToken, server: server)
            KeychainStore.set(nil, for: KeychainStore.refreshToken) // absent → 401s propagate, no refresh loop
        }
        // UI-test hook: reach the signed-in shell with no credential or reachable server. The sink
        // address lives in this process only (ServerURLStore.debugOverride): written to
        // UserDefaults it became the stored server, and every later launch — every UI test that
        // wants the real session — landed on the Connect screen.
        if CommandLine.arguments.contains("-kima-fake-signed-in") {
            ServerURLStore.debugOverride = "http://127.0.0.1:9"
            phase = .authenticated(host: "127.0.0.1:9")
            return
        }
        // Screenshot/verify hook for the unreachable gate without an actually-dead server.
        if CommandLine.arguments.contains("-kima-force-unreachable") {
            phase = .unreachable(host: ServerURLStore.current ?? "kima.example.com")
            return
        }
        #endif
        guard let urlString = ServerURLStore.current,
              let url = URL(string: urlString) else {
            phase = .unauthenticated
            return
        }
        let server = KimaServer(baseURL: url)
        KeychainStore.bindUnboundCredentials(to: server)
        // Only a credential saved for this address is sent to it. One saved for another server (a
        // sign-in that stopped before it stored its address) is refused: the user signs in again.
        guard let credential = KimaCredential.fromKeychain(for: server) else {
            phase = .unauthenticated
            return
        }
        let host = Self.displayHost(for: url, fallback: urlString)
        let client = KimaAPIClient(server: server, credential: credential)
        do {
            _ = try await client.me()
            phase = .authenticated(host: host)
        } catch APIError.unauthorized {
            // Both credentials are dead: the 401 interceptor in KimaAPIClient.send() already tried a refresh, so the
            // refresh token was invalid/revoked (and the interceptor wiped the tokens) or a device-link apiKey was
            // revoked. Deleting again is harmless; the trusted certificate stays.
            KeychainStore.clearCredentials()
            phase = .unauthenticated
        } catch APIError.network {
            // Server unreachable — offline, DNS/TLS failure, or (commonly for a self-hosted Kima on
            // Tailscale) the server's address CHANGED. Do NOT drop into a broken shell pointed at a
            // dead URL: show the unreachable gate (Retry / Change server address). Retry re-runs this
            // resume, so a brief blip recovers with one tap; a moved server gets a way to re-point.
            guard !Task.isCancelled else { return }
            phase = .unreachable(host: host)
        } catch {
            // The resume Task was cancelled (e.g. the splash was torn down) — leave state untouched.
            guard !Task.isCancelled else { return }
            // The server answered, but not with the account (non-401 4xx/5xx, or a body the app can't
            // read): every screen would fail, so the same gate offers retry and a new address.
            phase = .unreachable(host: host, serverError: (error as? APIError)?.errorDescription
                                 ?? "the server answered with an error.")
        }
    }

    /// Called by the connect flow after a successful sign-in / pairing (credential already persisted).
    func didAuthenticate() {
        guard let urlString = ServerURLStore.stored,
              let url = URL(string: urlString),
              KimaCredential.fromKeychain(for: KimaServer(baseURL: url)) != nil else {
            phase = .unauthenticated
            return
        }
        phase = .authenticated(host: Self.displayHost(for: url, fallback: urlString))
    }

    /// Re-point at a different server address without a full sign-out ceremony: keep the credential
    /// (same account, likely still valid) and drop to the connect flow so the user enters the new
    /// URL. Never touches the network, so it works even when the current server is dead.
    func changeServer() { phase = .unauthenticated }

    /// Clear local credentials and return to the connect flow. The server logout is best-effort and
    /// FIRED DETACHED — a dead / unreachable server (e.g. a changed Tailscale IP) must never block
    /// the return to the connect flow, which is exactly when the user needs it most.
    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        if let urlString = ServerURLStore.stored,
           let url = URL(string: urlString),
           let credential = KimaCredential.fromKeychain(for: KimaServer(baseURL: url)) {
            let client = KimaAPIClient(server: KimaServer(baseURL: url), credential: credential)
            Task { await client.logout() }   // best-effort; do not await a possibly-dead server
        }
        KeychainStore.clearCredentials()   // keeps the trusted certificate
        phase = .unauthenticated
    }
}
