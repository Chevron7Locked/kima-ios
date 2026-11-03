import XCTest
@testable import Kima

final class KimaServerTests: XCTestCase {
    private func server(_ s: String) -> KimaServer { KimaServer(baseURL: URL(string: s)!) }

    func testPlainBase() {
        XCTAssertEqual(server("https://h.example").api("/auth/me").absoluteString, "https://h.example/api/auth/me")
    }

    func testBasePathPrefixKept() {
        XCTAssertEqual(server("https://h.example/kima").api("/auth/me").absoluteString, "https://h.example/kima/api/auth/me")
        XCTAssertEqual(server("https://h.example/kima/").api("/auth/me").absoluteString, "https://h.example/kima/api/auth/me")
    }

    func testIPv6AndPort() {
        XCTAssertEqual(server("http://[::1]:3030").api("/auth/me").absoluteString, "http://[::1]:3030/api/auth/me")
    }

    func testDisplayHostKeepsThePortAndBracketsIPv6() {
        func display(_ s: String) -> String { SessionStore.displayHost(for: URL(string: s)!, fallback: s) }
        XCTAssertEqual(display("https://[::1]:8443"), "[::1]:8443")
        XCTAssertEqual(display("https://[fd00::5]"), "fd00::5")
        XCTAssertEqual(display("http://nas.lan:3030"), "nas.lan:3030")
        XCTAssertEqual(display("https://kima.example.com"), "kima.example.com")
    }

    func testPlusAndReservedInQueryValue() {
        let url = server("https://h.example").api("/search", query: ["q": "AC+DC & co=1"])
        XCTAssertEqual(url.query(percentEncoded: true), "q=AC%2BDC%20%26%20co%3D1")
    }

    func testPathSegmentSlashAndReserved() {
        XCTAssertEqual(KimaServer.pathSegment("AC/DC"), "AC%2FDC")
        XCTAssertEqual(KimaServer.pathSegment("a b"), "a%20b")
        XCTAssertEqual(KimaServer.pathSegment("a?b#c"), "a%3Fb%23c")
    }

    func testSlashNameAsSingleSegment() {
        let s = server("https://h.example")
        XCTAssertEqual(s.api("/artists/discover/\(KimaServer.pathSegment("AC/DC"))").absoluteString,
                       "https://h.example/api/artists/discover/AC%2FDC")
        XCTAssertEqual(s.api("/artists/discover/AC%2FDC").absoluteString, "https://h.example/api/artists/discover/AC%2FDC")
    }

    func testRawCharactersNeverCrash() {
        let s = server("https://h.example")
        XCTAssertEqual(s.api("/x/a b").absoluteString, "https://h.example/api/x/a%20b")
        XCTAssertEqual(s.api("/x/%zz").absoluteString, "https://h.example/api/x/%25zz")
        for raw in ["a?b", "a#b", "café", "100%", "é/ü?#% "] {
            let url = s.api("/x/\(raw)")
            XCTAssertEqual(url.host, "h.example")
            XCTAssertTrue(url.path.hasPrefix("/api/x/"))
        }
    }
}
