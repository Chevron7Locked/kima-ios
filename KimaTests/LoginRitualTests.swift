import XCTest
@testable import Kima

/// The establish-session ritual, tested once at its interface (ticket 11). The four steps run
/// in one order — store the credential, best-effort store the refresh token, erase other
/// servers' logins, persist the server address — and a failed credential store leaves nothing
/// else written. Sinks are recorded here; production sinks (real Keychain + stored address)
/// are exercised by the final-state tests.
final class LoginRitualTests: KeychainLoginTestCase {
    private let server = KimaServer(baseURL: URL(string: "https://ritual.example:3030")!)
    private let other = KimaServer(baseURL: URL(string: "https://other.example:3030")!)

    func testEstablishRunsTheStepsInOrder() {
        var events: [String] = []
        var savedCredentials: [String] = []
        let established = LoginRitual.establish(
            .jwt(accessToken: "access-1", refreshToken: "refresh-1"), at: server,
            saveCredential: { credential, _ in
                events.append("credential")
                if case .jwt(let accessToken, _) = credential { savedCredentials.append(accessToken) }
                return true
            },
            saveRefreshToken: { token, _ in events.append("refresh:\(token ?? "nil")"); return true },
            eraseOtherLogins: { _, _ in events.append("erase") },
            rememberServer: { _ in events.append("remember") }
        )
        XCTAssertTrue(established)
        XCTAssertEqual(events, ["credential", "refresh:refresh-1", "erase", "remember"])
        XCTAssertEqual(savedCredentials, ["access-1"])
    }

    func testFailedCredentialStoreWritesNothingElse() {
        var events: [String] = []
        let established = LoginRitual.establish(
            .jwt(accessToken: "access-1", refreshToken: "refresh-1"), at: server,
            saveCredential: { _, _ in events.append("credential"); return false },
            saveRefreshToken: { _, _ in events.append("refresh"); return true },
            eraseOtherLogins: { _, _ in events.append("erase") },
            rememberServer: { _ in events.append("remember") }
        )
        XCTAssertFalse(established)
        XCTAssertEqual(events, ["credential"])
    }

    func testFailingRefreshWriteIsBestEffort() {
        var events: [String] = []
        let established = LoginRitual.establish(
            .jwt(accessToken: "access-1", refreshToken: "refresh-1"), at: server,
            saveCredential: { _, _ in events.append("credential"); return true },
            saveRefreshToken: { _, _ in events.append("refresh"); return false },
            eraseOtherLogins: { _, _ in events.append("erase") },
            rememberServer: { _ in events.append("remember") }
        )
        XCTAssertTrue(established)
        XCTAssertEqual(events, ["credential", "refresh", "erase", "remember"])
    }

    func testApiKeyLoginClearsTheRefreshSlot() {
        var refreshed: [String] = []
        let established = LoginRitual.establish(
            .apiKey("device-key"), at: server,
            saveCredential: { _, _ in true },
            saveRefreshToken: { token, _ in refreshed.append(token ?? "nil"); return true },
            eraseOtherLogins: { _, _ in },
            rememberServer: { _ in }
        )
        XCTAssertTrue(established)
        XCTAssertEqual(refreshed, ["nil"])   // an API key has no refresh; the write deletes any stale one
    }

    func testJwtLoginLandsInTheRealStores() {
        // A previous login to another server, in every credential entry.
        XCTAssertTrue(KeychainStore.setCredential("old-key", for: KeychainStore.apiKey, server: other))
        XCTAssertTrue(KeychainStore.setCredential("old-access", for: KeychainStore.accessToken, server: other))
        XCTAssertTrue(KeychainStore.setCredential("old-refresh", for: KeychainStore.refreshToken, server: other))

        XCTAssertTrue(LoginRitual.establish(.jwt(accessToken: "access-1", refreshToken: "refresh-1"), at: server))

        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: server), "access-1")
        XCTAssertEqual(KeychainStore.credential(KeychainStore.refreshToken, for: server), "refresh-1")
        XCTAssertNil(KeychainStore.credential(KeychainStore.apiKey, for: server))
        XCTAssertNil(KeychainStore.credential(KeychainStore.accessToken, for: other))
        XCTAssertNil(KeychainStore.credential(KeychainStore.refreshToken, for: other))
        XCTAssertEqual(ServerURLStore.stored, "https://ritual.example:3030")
    }

    func testApiKeyLoginLandsInTheRealStores() {
        XCTAssertTrue(KeychainStore.setCredential("old-access", for: KeychainStore.accessToken, server: other))
        XCTAssertTrue(KeychainStore.setCredential("old-refresh", for: KeychainStore.refreshToken, server: other))

        XCTAssertTrue(LoginRitual.establish(.apiKey("device-key"), at: server))

        XCTAssertEqual(KeychainStore.credential(KeychainStore.apiKey, for: server), "device-key")
        XCTAssertNil(KeychainStore.credential(KeychainStore.accessToken, for: other))
        XCTAssertNil(KeychainStore.storedCredential(KeychainStore.refreshToken))
        XCTAssertEqual(ServerURLStore.stored, "https://ritual.example:3030")
    }

    func testJwtWithoutRefreshTokenLeavesNoStaleRefresh() {
        XCTAssertTrue(KeychainStore.setCredential("old-refresh", for: KeychainStore.refreshToken, server: other))

        XCTAssertTrue(LoginRitual.establish(.jwt(accessToken: "access-2", refreshToken: nil), at: server))

        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: server), "access-2")
        XCTAssertNil(KeychainStore.storedCredential(KeychainStore.refreshToken))
    }
}
