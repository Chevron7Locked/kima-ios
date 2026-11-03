import XCTest
@testable import Kima

/// A stored login is sent only to the server it came from. Sign-in saves the credential before the
/// server address; if the app dies in between, the next launch must not send the new server's
/// token to the old address. Runs against the test host's real Keychain and UserDefaults.
@MainActor
final class CredentialServerTests: XCTestCase {
    private let old = KimaServer(baseURL: URL(string: "https://kima-old.invalid")!)
    private let new = KimaServer(baseURL: URL(string: "https://kima-new.invalid:3443")!)
    private var savedLogin = KeychainLoginSnapshot()
    private var savedAddress: String?

    override func setUpWithError() throws {
        savedLogin = KeychainLoginSnapshot()
        savedAddress = UserDefaults.standard.string(forKey: "kima.serverURL")
        guard KeychainStore.setCredential("probe", for: KeychainStore.accessToken, server: old) else {
            throw XCTSkip("Keychain writes are unavailable in this test host")
        }
        XCTAssertTrue(KeychainStore.clearCredentials())
    }

    override func tearDown() {
        savedLogin.restore()
        UserDefaults.standard.set(savedAddress, forKey: "kima.serverURL")
    }

    func testCredentialIsReadOnlyForTheServerItWasSavedFor() {
        XCTAssertTrue(KeychainStore.setCredential("tok", for: KeychainStore.accessToken, server: new))
        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: new), "tok")
        XCTAssertNil(KeychainStore.credential(KeychainStore.accessToken, for: old))
        XCTAssertNil(KimaCredential.fromKeychain(for: old))
        guard case .jwt("tok")? = KimaCredential.fromKeychain(for: new) else { return XCTFail("own server refused") }
    }

    func testResumeRefusesTheNewServersTokenAtTheOldAddress() async {
        // Signed in to the old server, then a sign-in to the new one saved its token and the app
        // died before saving the new address.
        UserDefaults.standard.set(KeychainStore.serverID(old), forKey: "kima.serverURL")
        XCTAssertTrue(KeychainStore.setCredential("new-token", for: KeychainStore.accessToken, server: new))
        XCTAssertTrue(KeychainStore.setCredential("new-refresh", for: KeychainStore.refreshToken, server: new))

        let session = SessionStore()
        await session.resume()

        // Refused before any request: a request to the (unresolvable) old address would end unreachable.
        XCTAssertEqual(session.phase, .unauthenticated)
        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: new), "new-token",
                       "still bound to the new server, never rebound to the old address")
    }

    func testUnboundCredentialFromAnEarlierVersionBindsToTheStoredServerOnce() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "kima.test.binding"))
        defaults.removePersistentDomain(forName: "kima.test.binding")
        defer { defaults.removePersistentDomain(forName: "kima.test.binding") }
        XCTAssertTrue(KeychainStore.set("legacy", for: KeychainStore.accessToken))
        XCTAssertNil(KeychainStore.credential(KeychainStore.accessToken, for: old), "unbound is never sent")

        KeychainStore.bindUnboundCredentials(to: old, defaults: defaults)
        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: old), "legacy")

        // A pass has completed: an unbound item that appears later stays unbound, whatever the address.
        XCTAssertTrue(KeychainStore.set("later", for: KeychainStore.refreshToken))
        KeychainStore.bindUnboundCredentials(to: new, defaults: defaults)
        XCTAssertNil(KeychainStore.credential(KeychainStore.refreshToken, for: new), "bound after the one pass")
        XCTAssertNil(KeychainStore.credential(KeychainStore.accessToken, for: new), "a bound item is never rebound")
        XCTAssertEqual(KeychainStore.credential(KeychainStore.accessToken, for: old), "legacy")
    }

    func testSignOutClearsBoundCredentials() {
        XCTAssertTrue(KeychainStore.setCredential("tok", for: KeychainStore.accessToken, server: new))
        XCTAssertTrue(KeychainStore.setCredential("key", for: KeychainStore.apiKey, server: old))
        XCTAssertTrue(KeychainStore.clearCredentials())
        XCTAssertEqual(KeychainStore.read(KeychainStore.accessToken), .absent)
        XCTAssertEqual(KeychainStore.read(KeychainStore.apiKey), .absent)
    }
}
