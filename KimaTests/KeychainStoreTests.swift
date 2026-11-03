import XCTest
@testable import Kima

/// Sign-out deletes the login credentials only; a trusted certificate survives until the user
/// chooses "trust the new certificate". Runs against the test host's real Keychain.
final class KeychainStoreTests: XCTestCase {
    private let host = "pin-test.invalid"
    private let otherHost = "pin-test-2.invalid"
    private var saved = KeychainLoginSnapshot()

    override func setUpWithError() throws {
        saved = KeychainLoginSnapshot()
        // -34018 (no Keychain entitlement in an unsigned test host) fails every write.
        guard KeychainStore.set("probe", for: KeychainStore.certificatePinKey(host: host)) else {
            throw XCTSkip("Keychain writes are unavailable in this test host")
        }
    }

    override func tearDown() {
        saved.restore()
        KeychainStore.forgetTrustedCertificate(host: host)
        KeychainStore.forgetTrustedCertificate(host: otherHost)
    }

    func testClearCredentialsKeepsTrustedCertificates() {
        for key in KeychainStore.credentialKeys { XCTAssertTrue(KeychainStore.set("secret", for: key)) }
        XCTAssertTrue(KeychainStore.set("pin-a", for: KeychainStore.certificatePinKey(host: host)))

        XCTAssertTrue(KeychainStore.clearCredentials())

        for key in KeychainStore.credentialKeys { XCTAssertEqual(KeychainStore.read(key), .absent, key) }
        XCTAssertEqual(KeychainStore.read(KeychainStore.certificatePinKey(host: host)), .found("pin-a"))
    }

    func testRestoreKeepsTheCredentialsServer() {
        let server = KimaServer(baseURL: URL(string: "https://bound-test.invalid:3443")!)
        XCTAssertTrue(KeychainStore.setCredential("tok", for: KeychainStore.accessToken, server: server))
        let snapshot = KeychainLoginSnapshot()
        XCTAssertTrue(KeychainStore.clearCredentials())

        snapshot.restore()

        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: server), "tok")
        XCTAssertEqual(KeychainStore.storedCredential(KeychainStore.accessToken),
                       KeychainStore.StoredCredential(value: "tok", server: KeychainStore.serverID(server)))
    }

    func testClearCredentialsWhenNothingStoredSucceeds() {
        XCTAssertTrue(KeychainStore.clearCredentials())
        XCTAssertTrue(KeychainStore.clearCredentials())
    }

    func testForgetTrustedCertificateRemovesOnlyThatHost() {
        XCTAssertTrue(KeychainStore.set("pin-a", for: KeychainStore.certificatePinKey(host: host)))
        XCTAssertTrue(KeychainStore.set("pin-b", for: KeychainStore.certificatePinKey(host: otherHost)))
        XCTAssertTrue(KeychainStore.set("token", for: KeychainStore.accessToken))

        XCTAssertTrue(KeychainStore.forgetTrustedCertificate(host: host))

        XCTAssertEqual(KeychainStore.read(KeychainStore.certificatePinKey(host: host)), .absent)
        XCTAssertEqual(KeychainStore.read(KeychainStore.certificatePinKey(host: otherHost)), .found("pin-b"))
        XCTAssertEqual(KeychainStore.read(KeychainStore.accessToken), .found("token"))
    }

    func testClearCredentialsCanKeepTheNewLogin() {
        let server = KimaServer(baseURL: URL(string: "https://new.invalid")!)
        XCTAssertTrue(KeychainStore.setCredential("old-server-key", for: KeychainStore.apiKey, server: server))
        XCTAssertTrue(KeychainStore.setCredential("new-token", for: KeychainStore.accessToken, server: server))

        XCTAssertTrue(KeychainStore.clearCredentials(except: [KeychainStore.accessToken, KeychainStore.refreshToken]))

        XCTAssertEqual(KeychainStore.read(KeychainStore.apiKey), .absent)
        XCTAssertEqual(KeychainStore.read(KeychainStore.accessToken), .found("new-token"))
        guard case .jwt(let token)? = KimaCredential.fromKeychain(for: server) else { return XCTFail("the old API key still wins") }
        XCTAssertEqual(token, "new-token")
    }

    func testFirstInstallWipeRemovesCredentialsAndPins() {
        for key in KeychainStore.credentialKeys { XCTAssertTrue(KeychainStore.set("secret", for: key)) }
        XCTAssertTrue(KeychainStore.set("pin-a", for: KeychainStore.certificatePinKey(host: host)))
        XCTAssertTrue(KeychainStore.set("pin-b", for: KeychainStore.certificatePinKey(host: otherHost)))

        XCTAssertTrue(KeychainStore.clearAll())

        for key in KeychainStore.credentialKeys { XCTAssertEqual(KeychainStore.read(key), .absent, key) }
        XCTAssertEqual(KeychainStore.read(KeychainStore.certificatePinKey(host: host)), .absent)
        XCTAssertEqual(KeychainStore.read(KeychainStore.certificatePinKey(host: otherHost)), .absent)
    }

    func testPinKeyMatchesTheStoredAccountFormat() {
        XCTAssertEqual(KeychainStore.certificatePinKey(host: "kima.example.com"), "kima.certpin.kima.example.com")
    }

    func testReadTellsAbsentFromFound() {
        let key = KeychainStore.certificatePinKey(host: otherHost)
        XCTAssertEqual(KeychainStore.read(key), .absent)
        XCTAssertTrue(KeychainStore.set("pin-b", for: key))
        XCTAssertEqual(KeychainStore.read(key), .found("pin-b"))
    }
}
