import SwiftUI
import Observation

/// Drives the server-URL entry screen: normalize the address, hit /api/onboarding/status,
/// and decide whether the user creates the first account or connects to an existing one.
@MainActor
@Observable
final class ConnectViewModel {
    enum Phase: Equatable {
        case idle
        case checking
        case failed(String)
        case found(OnboardingStatus, host: String)
    }

    var urlText: String = ServerURLStore.stored ?? ""
    // Pre-fill the last-used server so re-onboarding (keychain cleared, reinstall, sign-out) doesn't need the address retyped.
    var phase: Phase = .idle
    private(set) var resolvedURL: String?   // the normalized URL that validated, for the next screen
    /// True while the insecure-connection confirmation sheet is presented.
    var showsInsecureAlert: Bool = false
    /// Set to true by `confirmInsecureConnection()` so the next `check()` call skips the gate.
    private var insecureConfirmed: Bool = false

    var canSubmit: Bool { !normalizedURL().isEmpty && phase != .checking }

    /// Accept "kima.example.com" or a full URL. With no scheme, pick one by host shape: IPv4/IPv6 literals,
    /// *.local and single-label names get http://, dotted public domains get https://.
    /// Text containing "://" is left untouched. The http:// confirmation gate (showsInsecureAlert) fires for any http URL.
    private func normalizedURL() -> String {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if text.contains("://") { return text }   // explicit scheme → leave untouched

        // No scheme given. Prefix https:// so URLComponents can extract the host, pick http or https by host shape,
        // then re-serialise cleanly. That drops any userinfo (never used; auth is JWT/API-key, and credentials
        // in a URL leak) and a trailing-dot FQDN, and handles :port and bracketed IPv6.
        // Falls back to a raw https prefix if the text does not parse as a URL.
        guard var comps = URLComponents(string: "https://\(text)"),
              let rawHost = comps.host, !rawHost.isEmpty else {
            return "https://\(text)"
        }
        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        comps.scheme = isLocalHost(host) ? "http" : "https"
        comps.host = host
        comps.user = nil
        comps.password = nil
        return comps.string ?? "\(comps.scheme ?? "https")://\(text)"
    }

    /// Returns true for host shapes that are almost certainly served over plain http:
    /// IPv4 literals, IPv6 literals (contain ":"), *.local mDNS names, and bare
    /// single-label names (no dots; common on intranets). Public dotted domains return false.
    private func isLocalHost(_ host: String) -> Bool {
        if host.contains(":") { return true }                            // IPv6 literal
        let lower = host.lowercased()
        if lower.hasSuffix(".local") { return true }                     // mDNS
        if !host.contains(".") { return true }                           // single label (e.g. "kima")
        let parts = host.split(separator: ".")
        if parts.count == 4, parts.allSatisfy({ Int($0) != nil }) { return true }  // IPv4
        return false
    }

    func check() async {
        guard phase != .checking else { return }   // ignore rapid double-taps / re-entrancy
        let raw = normalizedURL()
        guard let url = URL(string: raw),
              let host = url.host(), !host.isEmpty,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else {
            phase = .failed("that doesn't look like a valid web address.")
            return
        }
        // Gate only genuinely-PUBLIC http URLs behind the cleartext-credential confirmation. Private
        // networks (LAN / Tailscale / localhost — the normal self-hosted setup) don't warrant the
        // warning: there's no public path to leak into, and Tailscale is WireGuard-encrypted anyway.
        if scheme == "http", !NetworkTrust.isPrivateHost(host), !insecureConfirmed {
            showsInsecureAlert = true
            return
        }
        insecureConfirmed = false   // consume — don't carry confirmation across URL changes
        phase = .checking
        let client = KimaAPIClient(server: KimaServer(baseURL: url))
        do {
            let status = try await client.onboardingStatus()
            resolvedURL = raw
            phase = .found(status, host: host)
        } catch let error as APIError {
            phase = .failed(error.errorDescription ?? "couldn't connect.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Called when the user explicitly accepts the insecure-connection warning.
    func confirmInsecureConnection() async {
        insecureConfirmed = true
        await check()
    }
}
