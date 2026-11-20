import XCTest
@testable import Kima

/// `APIError.network` says why iOS refused, not just that it did (GitHub #1: every failure read
/// as "couldn't reach the server", so a declined permission looked like a typo or a dead server).
/// App-wide copy carries only reasons that read right on any screen; the address-specific ones
/// (name, port, timeout) are the connect screens' (`connectDescription`).
final class APIErrorNetworkReasonTests: XCTestCase {

    private let generic = "couldn't reach the server. check the address and your connection."

    private func copy(_ code: URLError.Code, userInfo: [String: Any] = [:]) -> String? {
        APIError.network(URLError(code, userInfo: userInfo)).errorDescription
    }

    func testDeniedLocalNetworkPermissionPointsAtTheSetting() {
        // Shape iOS returns when Local Network is off for the app: -1009 with the unsatisfied
        // path in _NSURLErrorNWPathKey — as logged in the wild, e.g. community.simon42.com/t/47931
        // "unsatisfied (Local network prohibited), interface: en0[802.11], ipv4, uses wifi".
        let msg = copy(.notConnectedToInternet, userInfo: [
            "_NSURLErrorNWPathKey": "unsatisfied (Local network prohibited), interface: en0[802.11], ipv4, uses wifi",
        ])
        XCTAssertEqual(msg, "iOS blocked Kima from your local network. turn it on in settings › privacy & security › local network.")
    }

    func testOfflineWithoutTheLocalNetworkReasonSaysOffline() {
        XCTAssertEqual(copy(.notConnectedToInternet), "you're offline. check your connection.")
    }

    func testCertificateFailures() {
        let expected = "the server's certificate isn't trusted. check its https setup, or use http on your local network."
        for code: URLError.Code in [.secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
                                    .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid] {
            XCTAssertEqual(copy(code), expected, "\(code)")
        }
    }

    func testAddressReasonsStayGenericOffTheConnectScreens() {
        for code: URLError.Code in [.cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .timedOut,
                                    .networkConnectionLost, .appTransportSecurityRequiresSecureConnection] {
            XCTAssertEqual(copy(code), generic, "\(code)")
        }
        XCTAssertEqual(APIError.network(NSError(domain: "KeychainStore", code: -1)).errorDescription, generic)
    }
}
