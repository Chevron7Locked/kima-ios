import XCTest
import Security
@testable import Kima

/// The self-signed certificate decision, and the Keychain read it rests on. A read error must never
/// be taken for "no pin stored": that would pin whatever key the server presents.
final class ServerTrustDecisionTests: XCTestCase {
    private let pin = "aa11"

    func testReadErrorRefusesAndNeverPins() {
        for status in [errSecInteractionNotAllowed, errSecMissingEntitlement, errSecDecode, errSecNotAvailable] {
            for hostMatches in [true, false] {
                XCTAssertEqual(
                    ServerTrustCoordinator.decide(stored: .failed(status), presented: pin, hostMatches: hostMatches),
                    .refuse, "status \(status), hostMatches \(hostMatches)"
                )
            }
        }
    }

    func testNothingStoredPinsOnlyWhenTheCertificateNamesTheHost() {
        XCTAssertEqual(ServerTrustCoordinator.decide(stored: .absent, presented: pin, hostMatches: true), .pinFirstUse)
        XCTAssertEqual(ServerTrustCoordinator.decide(stored: .absent, presented: pin, hostMatches: false), .refuse)
    }

    func testStoredPinAcceptsOnlyTheSameKeyAndName() {
        XCTAssertEqual(ServerTrustCoordinator.decide(stored: .found(pin), presented: pin, hostMatches: true), .accept)
        XCTAssertEqual(ServerTrustCoordinator.decide(stored: .found(pin), presented: "bb22", hostMatches: true),
                       .reportChange(keyChanged: true))
        XCTAssertEqual(ServerTrustCoordinator.decide(stored: .found(pin), presented: "bb22", hostMatches: false),
                       .reportChange(keyChanged: true))
        XCTAssertEqual(ServerTrustCoordinator.decide(stored: .found(pin), presented: pin, hostMatches: false),
                       .reportChange(keyChanged: false))
    }

    // MARK: - KeychainStore.read status mapping

    func testReadMapsNotFoundToAbsent() {
        XCTAssertEqual(KeychainStore.read("any") { _, _ in errSecItemNotFound }, .absent)
    }

    func testReadMapsEveryOtherErrorToFailed() {
        for status in [errSecInteractionNotAllowed, errSecMissingEntitlement, errSecAuthFailed, errSecNotAvailable] {
            XCTAssertEqual(KeychainStore.read("any") { _, _ in status }, .failed(status))
        }
    }

    func testReadReturnsTheStoredString() {
        let result = KeychainStore.read("any") { _, out in
            out?.pointee = Data("aa11".utf8) as CFData
            return errSecSuccess
        }
        XCTAssertEqual(result, .found("aa11"))
    }

    func testUnreadableDataIsAnErrorNotAbsent() {
        let result = KeychainStore.read("any") { _, out in
            out?.pointee = Data([0xFF, 0xFE, 0xFD]) as CFData
            return errSecSuccess
        }
        XCTAssertEqual(result, .failed(errSecDecode))
    }
}
