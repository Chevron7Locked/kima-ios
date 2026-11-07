import XCTest
@testable import Kima

final class DevicePairingLinkTests: XCTestCase {
    private func link(_ s: String) -> DevicePairingLink? {
        if case .link(let l) = DevicePairingLink.parse(s) { return l }
        return nil
    }

    func testWebFormatWithHttpsOrigin() {
        let l = link("kima://link?code=ABC234&server=https%3A%2F%2Flisten.chevron7.io")
        XCTAssertEqual(l?.code, "ABC234")
        XCTAssertEqual(l?.server.baseURL.absoluteString, "https://listen.chevron7.io")
        XCTAssertEqual(l?.isLoopback, false)
    }

    func testServerWithPortAndHttpLan() {
        XCTAssertEqual(link("kima://link?code=ABC234&server=https%3A%2F%2Fkima.example.com%3A3030")?.server.baseURL.absoluteString,
                       "https://kima.example.com:3030")
        let lan = link("kima://link?code=ABC234&server=http%3A%2F%2F192.168.1.20%3A3030")
        XCTAssertEqual(lan?.server.baseURL.absoluteString, "http://192.168.1.20:3030")
        XCTAssertEqual(lan?.usesCleartext, true)
    }

    func testTrailingSlashIsAcceptedAndDropped() {
        XCTAssertEqual(link("kima://link?code=ABC234&server=https%3A%2F%2Fa.example%2F")?.server.baseURL.absoluteString,
                       "https://a.example")
    }

    func testLowercaseCodeIsUppercased() {
        XCTAssertEqual(link("kima://link?code=abc234&server=https%3A%2F%2Fa.example")?.code, "ABC234")
    }

    func testLoopbackIsFlagged() {
        for host in ["localhost", "localhost.", "127.0.0.1", "127.1.2.3", "%5B%3A%3A1%5D",
                     "%5B%3A%3Affff%3A127.0.0.1%5D", "%5B%3A%3Affff%3A7f00%3A1%5D"] {
            let l = link("kima://link?code=ABC234&server=http%3A%2F%2F\(host)%3A3030")
            XCTAssertEqual(l?.isLoopback, true, host)
        }
    }

    func testPublicHostsAreNotLoopback() {
        for host in ["listen.chevron7.io", "192.168.1.20", "%5B%3A%3Affff%3A8.8.8.8%5D"] {
            let l = link("kima://link?code=ABC234&server=http%3A%2F%2F\(host)")
            XCTAssertEqual(l?.isLoopback, false, host)
        }
    }

    private func assertInvalid(_ s: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(DevicePairingLink.parse(s), .invalid, s, file: file, line: line)
    }

    func testRejectsBadServers() {
        let base = "kima://link?code=ABC234&server="
        assertInvalid(base + "ftp%3A%2F%2Fa.example")
        assertInvalid(base + "https%3A%2F%2Flisten.chevron7.io%40evil.com")
        assertInvalid(base + "https%3A%2F%2Fuser%3Apw%40a.example")
        assertInvalid(base + "https%3A%2F%2Fa.example%2Fkima")
        assertInvalid(base + "https%3A%2F%2Fa.example%3Fx%3D1")
        assertInvalid(base + "https%3A%2F%2Fa.example%23frag")
        assertInvalid(base + "https%3A%2F%2F")
        assertInvalid(base + "a.example")
        assertInvalid(base)
    }

    func testRejectsBadCodes() {
        let server = "&server=https%3A%2F%2Fa.example"
        for code in ["ABC23", "ABC2345", "ABC230", "ABCO34", "ABC134", "ABCI34", "ABC 34", ""] {
            assertInvalid("kima://link?code=\(code)" + server)
        }
    }

    func testRejectsMalformedLinkShapes() {
        let s = "https%3A%2F%2Fa.example"
        assertInvalid("kima://link?code=ABC234&code=DEF234&server=\(s)")
        assertInvalid("kima://link?code=ABC234&server=\(s)&server=\(s)")
        assertInvalid("kima://link?code=ABC234")
        assertInvalid("kima://link?server=\(s)")
        assertInvalid("kima://link")
        assertInvalid("kima://link/extra?code=ABC234&server=\(s)")
        assertInvalid("kima://link?code=ABC234&server=\(s)&extra=1")
        assertInvalid("kima://link?code=ABC234&server=\(s)#frag")
        assertInvalid("kima://link?code=ABC234&server=\(s)" + String(repeating: "a", count: 600))
    }

    func testNonPairingStrings() {
        for s in ["https://example.com", "hello", "", "kima://share/abcdefghijklmnop", "kima://queue",
                  "kimas://link?code=ABC234&server=https%3A%2F%2Fa.example", "kima://linkfoo?code=ABC234"] {
            XCTAssertEqual(DevicePairingLink.parse(s), .notPairing, s)
        }
    }

    func testURLOverloadMatchesString() {
        let url = URL(string: "kima://link?code=ABC234&server=https%3A%2F%2Fa.example")!
        XCTAssertNotNil(DevicePairingRequest(url: url))
        XCTAssertNil(DevicePairingRequest(url: URL(string: "kima://queue")!))
    }
}
