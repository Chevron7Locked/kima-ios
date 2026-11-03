import Foundation

/// Classifies a host as a trusted private network (localhost, LAN, Tailscale), where plain `http` is the normal
/// self-hosted setup and not a real exposure. Keeps the connection-security UI honest: `http` there shows as
/// "Private network", not the "not encrypted" warning. A messaging classifier, deliberately conservative:
/// anything not positively private is treated as public.
enum NetworkTrust {
    static func isPrivateHost(_ host: String?) -> Bool {
        guard var h = host?.lowercased(), !h.isEmpty else { return false }
        // Strip IPv6 literal brackets, e.g. "[fe80::1]".
        if h.hasPrefix("["), h.hasSuffix("]") { h = String(h.dropFirst().dropLast()) }

        // Hostname forms.
        if h == "localhost" || h.hasSuffix(".localhost") { return true }
        if h.hasSuffix(".local") { return true }            // mDNS / Bonjour
        if h.hasSuffix(".ts.net") { return true }           // Tailscale MagicDNS
        if h.hasSuffix(".lan") || h.hasSuffix(".home") || h.hasSuffix(".internal") { return true }
        // NOTE: a bare single-label host (e.g. "kima") is deliberately NOT treated as private —
        // it's indistinguishable by name from a public TLD ("com", "io"), and under-warning a
        // public cleartext connection is the security-worse error. Private LAN boxes should be
        // reached by IP or a private suffix (.local / .lan / .ts.net), which ARE recognised above.

        // IPv6 literals.
        if h.contains(":") {
            if h == "::1" { return true }                   // loopback
            if h.hasPrefix("fe80") { return true }          // link-local fe80::/10
            if h.hasPrefix("fc") || h.hasPrefix("fd") { return true }  // unique-local fc00::/7
            return false
        }

        // IPv4 dotted quad — every octet must be a number in 0...255.
        let parts = h.split(separator: ".")
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (127, _):            return true               // loopback 127.0.0.0/8
        case (10, _):             return true               // RFC1918 10.0.0.0/8
        case (192, 168):          return true               // RFC1918 192.168.0.0/16
        case (172, 16...31):      return true               // RFC1918 172.16.0.0/12
        case (169, 254):          return true               // link-local 169.254.0.0/16
        case (100, 64...127):     return true               // CGNAT / Tailscale 100.64.0.0/10
        default:                  return false
        }
    }
}
