import XCTest
@testable import Kima

/// The shared posture for suites that write real logins: snapshot the simulator's login and
/// stored address, start every test from nothing (no credentials, no stored address), hard-
/// assert Keychain writability (ticket 10 ruling: no environment-dependent skips), and put
/// everything back afterwards. `StubURLProtocol.reset()` runs on both ends so HTTP state can
/// never leak across suites that share the process. Main-actor so subclasses' setUp overrides
/// inherit that isolation (the sign-in view models under test are @MainActor).
@MainActor
class KeychainLoginTestCase: XCTestCase {
    private var savedLogin = KeychainLoginSnapshot()

    override func setUpWithError() throws {
        StubURLProtocol.reset()
        savedLogin = KeychainLoginSnapshot()
        UserDefaults.standard.removeObject(forKey: ServerURLStore.key)   // snapshot holds the real address
        let probe = KimaServer(baseURL: URL(string: "https://keychain-probe.invalid")!)
        XCTAssertTrue(KeychainStore.setCredential("probe", for: KeychainStore.apiKey, server: probe),
                      "Keychain writes must work in the test host (ticket 10 ruling: no environment-dependent skips)")
        XCTAssertTrue(KeychainStore.clearCredentials())
    }

    override func tearDown() {
        StubURLProtocol.reset()
        savedLogin.restore()
    }
}
