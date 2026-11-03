import Foundation
import Security

/// Whether a self-signed leaf certificate names the host the app connected to. SAN DNS names
/// match exactly or by a single-label wildcard; SAN IP addresses and IP-literal hosts compare as
/// address bytes, so `::1`, `[::1]` and `0:0:0:0:0:0:0:1` are one host. The CN counts only when
/// the SAN lists no names at all (RFC 6125 §6.4.4); a SAN that cannot be read matches nothing.
enum CertificateHostNames {
    /// True when `certificate` names `host`.
    static func certificate(_ certificate: SecCertificate, names host: String) -> Bool {
        leaf(SecCertificateCopyData(certificate) as Data,
             subjectSummary: SecCertificateCopySubjectSummary(certificate) as String?,
             names: host)
    }

    /// True when the leaf certificate (DER) names `host`; `subjectSummary` is its CN.
    static func leaf(_ der: Data, subjectSummary: String?, names host: String) -> Bool {
        let b = [UInt8](der)
        let san = sanSequence(in: b)
        if case .malformed = san { return false }   // never fall back to the CN past an unreadable SAN
        let ips = ipAddresses(in: b, san)
        let hostAddress = ipAddress(host)
        if let hostAddress, ips.contains(hostAddress) { return true }
        var names = dnsNames(in: b, san).map { $0.lowercased() }
        if names.isEmpty {
            if !ips.isEmpty { return false }   // an IP-only SAN is authoritative: no CN fallback
            if let subjectSummary { names = [subjectSummary.lowercased()] }
        }
        let h = host.lowercased()
        return names.contains { name in
            if let hostAddress, let nameAddress = ipAddress(name) { return nameAddress == hostAddress }
            return certName(name, matches: h)
        }
    }

    /// The address bytes of an IP literal: "10.0.0.2", "::1", "[::1]", "fe80::1%en0". The zone is
    /// dropped (it names a local interface and is never in a certificate); an IPv4-mapped IPv6
    /// address ("::ffff:10.0.0.2") gives its IPv4 bytes. Nil for a DNS name.
    static func ipAddress(_ host: String) -> [UInt8]? {
        var s = Substring(host)
        if s.hasPrefix("["), s.hasSuffix("]") { s = s.dropFirst().dropLast() }
        if s.contains(":"), let zone = s.firstIndex(of: "%") { s = s[..<zone] }
        let text = String(s)
        var v4 = in_addr()
        if inet_pton(AF_INET, text, &v4) == 1 { return withUnsafeBytes(of: &v4) { Array($0) } }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, text, &v6) == 1 { return canonical(withUnsafeBytes(of: &v6) { Array($0) }) }
        return nil
    }

    /// IPv4-mapped IPv6 bytes (::ffff:a.b.c.d) as the 4 IPv4 bytes; any other address unchanged.
    private static func canonical(_ a: [UInt8]) -> [UInt8] {
        guard a.count == 16, a[0 ..< 10].allSatisfy({ $0 == 0 }), a[10] == 0xFF, a[11] == 0xFF else { return a }
        return Array(a[12 ..< 16])
    }

    // MARK: - SAN walk

    /// SAN entries with a given tag (0x82 dNSName, 0x87 iPAddress), walking the
    /// whole GeneralNames SEQUENCE — entry types may appear in any order.
    private static func sanEntries<T>(_ b: [UInt8], _ san: SAN, tag: UInt8, format: ([UInt8]) -> T?) -> [T] {
        guard case .names(let body, let end) = san else { return [] }
        var i = body
        var out: [T] = []
        while i < end {
            guard i < b.count, b[i] >= 0x80, let (len, body) = derLength(b, i + 1),
                  body + len <= end else { break }   // any context tag; bounds first
            if b[i] == tag, let s = format(Array(b[body ..< body + len])) { out.append(s) }
            i = body + len
        }
        return out
    }

    private static func dnsNames(in b: [UInt8], _ san: SAN) -> [String] {
        sanEntries(b, san, tag: 0x82) { String(bytes: $0, encoding: .utf8) }
    }

    /// SAN IP entries as address bytes (4 for IPv4, 16 for IPv6; IPv4-mapped entries as IPv4).
    private static func ipAddresses(in b: [UInt8], _ san: SAN) -> [[UInt8]] {
        sanEntries(b, san, tag: 0x87) { $0.count == 4 || $0.count == 16 ? canonical($0) : nil }
    }

    /// The certificate's SAN: not there (v1 certificate, or no such extension), not readable, or
    /// the span of its GeneralNames entries.
    private enum SAN { case absent, malformed, names(body: Int, end: Int) }

    /// Locate the SAN extension's inner SEQUENCE by a TOP-DOWN walk of the certificate DER, not a
    /// byte search: the SAN OID pattern can appear inside other bytes (e.g. the attacker-writable
    /// serial) and must never be honored as a fake extension. Anything structurally odd is
    /// `.malformed`; a certificate with no extensions, or none of them a SAN, is `.absent`.
    private static func sanSequence(in b: [UInt8]) -> SAN {
        let oid: [UInt8] = [0x06, 0x03, 0x55, 0x1D, 0x11]
        var p = b.startIndex
        guard let cert = tlv(b, at: &p), cert.tag == 0x30 else { return .malformed }   // Certificate SEQUENCE
        p = cert.body
        guard let tbs = tlv(b, at: &p), tbs.tag == 0x30 else { return .malformed }     // TBSCertificate SEQUENCE
        var q = tbs.body
        guard q < tbs.end else { return .malformed }
        if b[q] == 0xA0 { guard tlv(b, at: &q) != nil else { return .malformed } }     // [0] version (optional)
        // serial INTEGER, signature SEQ, issuer SEQ, validity SEQ, subject SEQ, SPKI SEQ
        for _ in 0 ..< 6 { guard tlv(b, at: &q) != nil else { return .malformed } }
        // [1]/[2] unique IDs — rare; skip when present
        while q < tbs.end, b[q] == 0xA1 || b[q] == 0xA2 {
            guard tlv(b, at: &q) != nil else { return .malformed }
        }
        guard q < tbs.end, b[q] == 0xA3 else { return .absent }                     // no [3] extensions
        guard let explicit = tlv(b, at: &q) else { return .malformed }
        var x = explicit.body
        guard let exts = tlv(b, at: &x), exts.tag == 0x30 else { return .malformed }  // Extensions SEQUENCE inside [3]
        var e = exts.body
        while e < exts.end, b[e] == 0x30 {
            guard let entry = tlv(b, at: &e) else { return .malformed }   // advances past this extension
            var inner = entry.body
            guard inner + oid.count <= entry.end,
                  Array(b[inner ..< inner + oid.count]) == oid else { continue }  // not SAN — already skipped
            inner += oid.count
            if inner + 2 <= entry.end, b[inner] == 0x01, b[inner + 1] == 0x01 { inner += 3 }  // critical BOOLEAN TRUE
            guard inner < entry.end, b[inner] == 0x04,
                  let (olen, octetBody) = derLength(b, inner + 1),
                  octetBody + olen <= entry.end,                 // octet contents stay inside the entry
                  octetBody < entry.end,                         // an empty octet has no SEQUENCE to read
                  b[octetBody] == 0x30,                          // GeneralNames SEQUENCE
                  let (slen, namesBody) = derLength(b, octetBody + 1),
                  namesBody <= octetBody + olen                  // seq stays inside the octet
            else { return .malformed }
            let end = min(octetBody + olen, namesBody + slen)
            return namesBody < end ? .names(body: namesBody, end: end) : .malformed   // any types, any order
        }
        return e == exts.end ? .absent : .malformed
    }

    /// TLV at position `p` (tag + definite length + body span). Advances `p`
    /// past the whole TLV on success; nil when bounds/lengths are malformed.
    private static func tlv(_ b: [UInt8], at p: inout Int) -> (tag: UInt8, body: Int, end: Int)? {
        guard p < b.count else { return nil }
        let tag = b[p]
        guard let (len, body) = derLength(b, p + 1), body + len <= b.count, len >= 0 else { return nil }
        p = body + len
        return (tag, body, body + len)
    }

    /// DER definite-length header at i: short (<0x80) or 1/2-byte long form.
    private static func derLength(_ b: [UInt8], _ i: Int) -> (Int, Int)? {
        guard i < b.count else { return nil }
        let first = b[i]
        if first < 0x80 { return (Int(first), i + 1) }
        let nbytes = Int(first & 0x7F)
        guard nbytes > 0, nbytes <= 2, i + 1 + nbytes <= b.count else { return nil }
        var len = 0
        for k in 0..<nbytes { len = (len << 8) | Int(b[i + 1 + k]) }
        return (len, i + 1 + nbytes)
    }

    /// One DNS name from the cert vs one host: exact, or a leftmost `*.` wildcard binding exactly one
    /// label (RFC 6125 §6.4.3: `*.example.com` never matches `a.b.example.com`). A single-label base
    /// (`*.lan` → `nas.lan`, as LAN appliances issue) and a bare-TLD base are accepted: only
    /// self-signed leaves that already passed the key pin get here.
    private static func certName(_ pattern: String, matches host: String) -> Bool {
        if pattern.hasPrefix("*."), !pattern.dropFirst(2).contains("*") {
            let base = String(pattern.dropFirst(2))
            guard !base.isEmpty, base.first != ".", base.last != "." else { return false }
            // Host must end with ".base"...
            guard host.count > base.count + 1, host.hasSuffix("." + base) else { return false }
            let prefix = String(host.dropLast(base.count + 1))
            return !prefix.contains(".")   // ...with exactly one label before it
        }
        return pattern == host
    }
}
