import SwiftUI

// MARK: - ConnectionSecurityBadge

/// Compact connection-security indicator. Encrypted (https): muted lock. Private network (http to a
/// trusted LAN/Tailscale/localhost host, see `NetworkTrust`): calm house glyph, not a warning.
/// Not encrypted (http to a public host): lock.slash + "HTTP · not encrypted" in a warm caution
/// tone, never red; reserved for cleartext credentials over the open internet.
struct ConnectionSecurityBadge: View {
    private enum State { case encrypted, privateNetwork, insecure }
    private let state: State

    /// Classify from a URL's scheme + host. `https` → encrypted; `http` to a trusted private host
    /// → private network; anything else (public http, unknown) → not encrypted.
    init(scheme: String?, host: String?) {
        switch scheme?.lowercased() {
        case "https":
            state = .encrypted
        case "http" where NetworkTrust.isPrivateHost(host):
            state = .privateNetwork
        default:
            state = .insecure
        }
    }

    var body: some View {
        switch state {
        case .encrypted:      calmLabel(icon: "lock.fill", text: "encrypted")
        case .privateNetwork: calmLabel(icon: "house.fill", text: "private network")
        case .insecure:       insecureLabel
        }
    }

    // MARK: - Private views

    /// The reassuring, minimal treatment shared by the two "you're fine" states — muted bone,
    /// no capsule, no colour. Encrypted and private-network differ only by glyph + word.
    private func calmLabel(icon: String, text: String) -> some View {
        Label {
            Text(text)
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(KimaColor.textMuted)
        }
    }

    private var insecureLabel: some View {
        Label {
            Text("http · not encrypted")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.caution.opacity(0.85))
        } icon: {
            Image(systemName: "lock.slash.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(KimaColor.caution.opacity(0.85))
        }
        .padding(.horizontal, KimaSpacing.sm)
        .padding(.vertical, KimaSpacing.xs)
        .background(KimaColor.caution.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(KimaColor.caution.opacity(0.22), lineWidth: 0.5))
    }
}

// MARK: - Preview

#Preview("States") {
    VStack(spacing: KimaSpacing.lg) {
        ConnectionSecurityBadge(scheme: "https", host: "kima.example.com")   // Encrypted
        ConnectionSecurityBadge(scheme: "http",  host: "192.168.1.20")        // Private network
        ConnectionSecurityBadge(scheme: "http",  host: "myserver.ts.net")     // Private network
        ConnectionSecurityBadge(scheme: "http",  host: "203.0.113.7")         // Not encrypted (public)
    }
    .padding()
    .background(KimaColor.base)
}
