import XCTest
import Security
@testable import Kima

/// Self-signed certificates name the host the app connected to, IPv6 included: the host and the
/// certificate's IP entries compare as addresses, whatever way each one is written.
final class CertificateHostNamesTests: XCTestCase {
    // Self-signed test certificates (EC P-256), DER as base64. SAN shown beside each.
    private let v6Loopback = "MIIBeTCCAR+gAwIBAgIUDHDAWzTSdsTwKkRW9M5Y925Oyg0wCgYIKoZIzj0EAwIwFDESMBAGA1UEAwwJa2ltYSB0ZXN0MB4XDTI2MTAwOTA3MTI0NFoXDTM2MTAwNjA3MTI0NFowFDESMBAGA1UEAwwJa2ltYSB0ZXN0MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAElKJSifZw3exd+Y1ol79C8C5uhV8MJpjBOPe0ruvIuFPnCq3o+YvZQbcOyscI4YEJWEdkAqyGYZWD4z+XTPhvmaNPME0wHQYDVR0OBBYEFHa8hDEMSM0P7QMErCTcAtlNpQVFMA8GA1UdEwEB/wQFMAMBAf8wGwYDVR0RBBQwEocQAAAAAAAAAAAAAAAAAAAAATAKBggqhkjOPQQDAgNIADBFAiEAkcskW6r7z15qaEuK8hQwnT4zazHTca+lqN5YS9lJ6c8CIC2rDt1nB6/hqpc5FNYBFR923X5ghfDg9FpNvXpxetDb"          // IP:::1
    private let v6Full = "MIIBeTCCAR+gAwIBAgIULlm/SKDnDhsoYtn0XzBn4x64UCwwCgYIKoZIzj0EAwIwFDESMBAGA1UEAwwJa2ltYSB0ZXN0MB4XDTI2MTAwOTA3MTI0NFoXDTM2MTAwNjA3MTI0NFowFDESMBAGA1UEAwwJa2ltYSB0ZXN0MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEs6Ci/5RUU25vDaHiV7+uc39tKUlZyUMpPVMue844reL2VC/9kkdtTyV4AgO2+vd5GJhgKWcnHTOJTtw/nHLkHKNPME0wHQYDVR0OBBYEFAXV8VrdWVYH+JmX0kUgkT/SRkT0MA8GA1UdEwEB/wQFMAMBAf8wGwYDVR0RBBQwEocQIAENuIWjAAAAAIouA3BzNDAKBggqhkjOPQQDAgNIADBFAiB02W+tWKSjjUEIaQbTjNWekupkAObzxsLVkZamzojl4gIhAMn3bPea2TrGeq7595Hit4tovJdtl8qsog79v5JGopk8"              // IP:2001:db8:85a3::8a2e:370:7334
    private let mixed = "MIIBiTCCAS6gAwIBAgIUKEQVioo/rn3c1RkQ/ltz+E6asCswCgYIKoZIzj0EAwIwFDESMBAGA1UEAwwJa2ltYSB0ZXN0MB4XDTI2MTAwOTA3MTI0NFoXDTM2MTAwNjA3MTI0NFowFDESMBAGA1UEAwwJa2ltYSB0ZXN0MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEhA4j/UaNAZDSe8OjArP6cQSLUK1RzBre6fRGdaJjbAlphSsZ7VeyP43InGabhrbCS8Swg120pXEPFgy2AhS8nKNeMFwwHQYDVR0OBBYEFECzNK0U5/qxJn7bSugbmkk9mE7LMA8GA1UdEwEB/wQFMAMBAf8wKgYDVR0RBCMwIYIHbmFzLmxhbocEwKgBBYcQ/QAAAAAAAAAAAAAAAAAABTAKBggqhkjOPQQDAgNJADBGAiEAqPzOnwNpUZBqU0a0a09tbFL91sqMHDFLJlC16dd7K8kCIQCMwGUlSfplB70DpV+W+kzcmHM/RLkAWA6N2ti0dG/MhA=="                // DNS:nas.lan, IP:192.168.1.5, IP:fd00::5
    private let cnOnlyV6 = "MIIBTjCB9qADAgECAhQFPfWWeJO5GorcyhVXoGLLur3N8TAKBggqhkjOPQQDAjAOMQwwCgYDVQQDDAM6OjEwHhcNMjYxMDA5MDcxMjQ0WhcNMzYxMDA2MDcxMjQ0WjAOMQwwCgYDVQQDDAM6OjEwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASRDvEGafavjBVHcVxHG9XmPQmGqUCvNnKEbWZsxRFkmLe5Cpp/JgMGlOQcaJB/JUAXpVFWpWH7AD9C6+GFkyI8ozIwMDAdBgNVHQ4EFgQUOw1lHcM/5y7PNFhSWVE+qPMmDAkwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNHADBEAiBWD0S2lgmzfQLmoqDQtCFVP1kOwxMr8/qHcZYKkZwFIAIgRwegNPObATbIOyyFKkFXoBO3RaMeqvJGlLy8xmjFAbM="              // no SAN, CN=::1
    private let wildcard = "MIIBbTCCARSgAwIBAgIUYbqTKvQGwh9ZjHF/fFsoFDAjtk4wCgYIKoZIzj0EAwIwFDESMBAGA1UEAwwJa2ltYSB0ZXN0MB4XDTI2MTAwOTA3MTI0NFoXDTM2MTAwNjA3MTI0NFowFDESMBAGA1UEAwwJa2ltYSB0ZXN0MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE/yV3KZPczuc13gDYqvLPpxHezMhH0jdgbM7/JOw9hS8DdRXirsIeKuW2YoQaC3lbyPiz/hw/StL0ojcJFqsskKNEMEIwHQYDVR0OBBYEFLQKyM665M9iohJzX72MbqN7BC5JMA8GA1UdEwEB/wQFMAMBAf8wEAYDVR0RBAkwB4IFKi5sYW4wCgYIKoZIzj0EAwIDRwAwRAIgazfB906iOKYY0AJb+4Flp6NvDlI2bug1In0f/nxH/z0CIAHYvnSDQgg6NFoEFOHJ7U/ecXRmjF6EhNhmAkoxKBc9"              // DNS:*.lan
    private let v4Only = "MIIC+TCCAeGgAwIBAgIUL6SrrH7mE3zBXtQOOk8RJd7gUHQwDQYJKoZIhvcNAQELBQAwFDESMBAGA1UEAwwJMTI3LjAuMC4xMB4XDTI2MTAwOTAyMDMwNFoXDTI2MTAxMjAyMDMwNFowFDESMBAGA1UEAwwJMTI3LjAuMC4xMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtVD9oqPVw/UsfzsWCKV09lmAVsUQLaSGueTuu/B6iWdaalG/VQocCrjGJQo40xxW1CPXqIe7JvSSjBP3g6KqRX2XrIn+ms22ZhhGwFlHDJOKAJGtg3Mq4+BNa19oJRgeuLeSfd+hrYoYHh+BDqCeyDwIOFTay2L8Z0b7/tfBrwl6FtbqRvtNI6FGaGZ9katq0UJUMl4YDjpu9LAP81VR/IDid99NRYqYN6/ry7zWoLekYJ2xEvJGgXrU4k4pzC8tTwcZel6OIlYv5umtSJLEP/cu/0FeiNh3lfX2F8QewFdXmmKe9pbQaA2R/HiOdvMMoGGd6pfTjLV+Qxed0FcU5wIDAQABo0MwQTAdBgNVHQ4EFgQU01g8Emiy2GfMogTKSwPDXH/x0lQwDwYDVR0TAQH/BAUwAwEB/zAPBgNVHREECDAGhwR/AAABMA0GCSqGSIb3DQEBCwUAA4IBAQCO6/LkdfUcdgNUSKRwyA4TexJmcL5r8qa60Nxij+c0R/YgOFDPehF8bFIRuZzfJafMgwjs9a+jzrUJFKpxcGVBlg06ToGcB9QHjYGGm1JFc2I2X5PfT1Kqr7FD0AenG223gXZm7cwxl76S78jEO7rg0JRMHSoxdWkoG+s7xgXAOzgyp1uFJMKco5LD2sjbfn3TBpGyq+9bFDpovA5oMw89UTfM3O4ngMI80VdeXovBawgludFJ683kYXGodN4QqV1ypqyso/jtD3rP9jA93+11ixf45m/LVwAblws/z61Mw5rj/MiKTKq4nocTbeWxh4YCbsC8kPKbfwh1Edyuehj/"                  // IP:127.0.0.1, CN=127.0.0.1

    private func cert(_ base64: String) throws -> SecCertificate {
        let der = try XCTUnwrap(Data(base64Encoded: base64))
        return try XCTUnwrap(SecCertificateCreateWithData(nil, der as CFData))
    }

    private func names(_ base64: String, _ host: String) throws -> Bool {
        CertificateHostNames.certificate(try cert(base64), names: host)
    }

    func testLoopbackV6MatchesEveryWayOfWritingIt() throws {
        for host in ["::1", "[::1]", "0:0:0:0:0:0:0:1", "0000:0000:0000:0000:0000:0000:0000:0001", "::1%lo0", "[::1%25lo0]"] {
            XCTAssertTrue(try names(v6Loopback, host), host)
        }
        XCTAssertFalse(try names(v6Loopback, "::2"))
        XCTAssertFalse(try names(v6Loopback, "127.0.0.1"))
    }

    func testFullV6MatchesCompressedExpandedAndUppercase() throws {
        for host in ["2001:db8:85a3::8a2e:370:7334", "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
                     "[2001:DB8:85A3::8A2E:370:7334]", "2001:db8:85a3:0:0:8a2e:370:7334"] {
            XCTAssertTrue(try names(v6Full, host), host)
        }
        XCTAssertFalse(try names(v6Full, "2001:db8:85a3::8a2e:370:7335"))
    }

    func testIPHostMatchesAnIPEntryNextToDNSNames() throws {
        XCTAssertTrue(try names(mixed, "nas.lan"))
        XCTAssertTrue(try names(mixed, "NAS.lan"))
        XCTAssertTrue(try names(mixed, "192.168.1.5"))
        XCTAssertTrue(try names(mixed, "[fd00::5]"))
        XCTAssertTrue(try names(mixed, "fd00:0:0:0:0:0:0:5"))
        XCTAssertFalse(try names(mixed, "192.168.1.6"))
        XCTAssertFalse(try names(mixed, "other.lan"))
    }

    func testCommonNameFallbackComparesAddresses() throws {
        XCTAssertTrue(try names(cnOnlyV6, "[::1]"))
        XCTAssertTrue(try names(cnOnlyV6, "0:0:0:0:0:0:0:1"))
        XCTAssertFalse(try names(cnOnlyV6, "::2"))
    }

    func testIPv4AndWildcardsStillMatchAsBefore() throws {
        XCTAssertTrue(try names(v4Only, "127.0.0.1"))
        XCTAssertFalse(try names(v4Only, "127.0.0.2"))
        XCTAssertFalse(try names(v4Only, "localhost"), "an IP-only SAN keeps the CN out")
        XCTAssertTrue(try names(wildcard, "nas.lan"))
        XCTAssertFalse(try names(wildcard, "a.nas.lan"), "a wildcard binds one label")
        XCTAssertFalse(try names(wildcard, "lan"))
    }

    /// The SAN itself is read (the entries sit inside the extensions' own SEQUENCE), so a certificate
    /// that lists names never falls back to its CN, whatever Security reports as its summary.
    func testSANEntriesAreReadAndTheCommonNameIgnored() throws {
        func leaf(_ base64: String, _ summary: String, _ host: String) throws -> Bool {
            CertificateHostNames.leaf(try XCTUnwrap(Data(base64Encoded: base64)), subjectSummary: summary, names: host)
        }
        XCTAssertTrue(try leaf(mixed, "kima test", "nas.lan"))
        XCTAssertTrue(try leaf(mixed, "kima test", "192.168.1.5"))
        XCTAssertFalse(try leaf(mixed, "kima test", "kima test"), "CN used although the SAN lists names")
        XCTAssertTrue(try leaf(wildcard, "kima test", "nas.lan"))
        XCTAssertFalse(try leaf(wildcard, "nas.lan", "other.lan.example"), "summary must not stand in for the SAN")
        XCTAssertTrue(try leaf(v6Loopback, "kima test", "::1"))
        XCTAssertFalse(try leaf(v6Loopback, "::2", "::2"), "an IP-only SAN keeps the CN out")
    }

    func testIPv4MappedHostMatchesTheIPv4Entry() throws {
        XCTAssertTrue(try names(mixed, "::ffff:192.168.1.5"))
        XCTAssertTrue(try names(mixed, "[::ffff:c0a8:105]"))
        XCTAssertFalse(try names(mixed, "::ffff:192.168.1.6"))
        XCTAssertEqual(CertificateHostNames.ipAddress("::ffff:10.0.0.2"), [10, 0, 0, 2])
    }

    /// A SAN that cannot be read matches nothing, even when the CN (or summary) names the host.
    func testUnreadableSANNeverFallsBackToTheCommonName() throws {
        var der = [UInt8](try XCTUnwrap(Data(base64Encoded: mixed)))
        let oid: [UInt8] = [0x06, 0x03, 0x55, 0x1D, 0x11]
        let at = try XCTUnwrap((0 ... der.count - oid.count).first { Array(der[$0 ..< $0 + oid.count]) == oid })
        let names = at + oid.count + 2                  // OCTET STRING tag + length, then GeneralNames
        XCTAssertEqual(der[names], 0x30)
        der[names] = 0x31                               // GeneralNames no longer a SEQUENCE
        XCTAssertFalse(CertificateHostNames.leaf(Data(der), subjectSummary: "nas.lan", names: "nas.lan"))
        XCTAssertTrue(CertificateHostNames.leaf(try XCTUnwrap(Data(base64Encoded: mixed)),
                                                subjectSummary: "nas.lan", names: "nas.lan"), "control")
    }

    func testAddressParsing() {
        XCTAssertEqual(CertificateHostNames.ipAddress("10.0.0.2"), [10, 0, 0, 2])
        XCTAssertEqual(CertificateHostNames.ipAddress("[::1]"), Array(repeating: 0, count: 15) + [1])
        XCTAssertEqual(CertificateHostNames.ipAddress("fe80::1%en0"), [0xfe, 0x80] + Array(repeating: 0, count: 13) + [1])
        XCTAssertNil(CertificateHostNames.ipAddress("nas.lan"))
        XCTAssertNil(CertificateHostNames.ipAddress("10.0.0"))
        XCTAssertNil(CertificateHostNames.ipAddress("10.0.0.2%en0"), "a zone only follows an IPv6 address")
    }
}
