import XCTest

/// The certificate-alert story on the real view tree, driven by the `-kima-fake-cert-changed`
/// hook; no server. Two servers change at once: the first alert stays until answered, then the
/// second shows. And a change reported while the link-a-device sheet is up must still reach the
/// user — both alert attachments bind the one `ServerTrustState`, and answering anywhere settles
/// it everywhere.
final class CertificateAlertUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() { continueAfterFailure = false }

    override func tearDown() { app.terminate() }

    private func alertNaming(_ host: String) -> XCUIElement {
        app.alerts.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", host)).firstMatch
    }

    @MainActor
    func testSecondHostShowsAfterTheFirstIsAnswered() throws {
        app.launchArguments = ["-kima-fake-cert-changed", "first.lan,second.lan"]
        app.launch()

        XCTAssertTrue(alertNaming("first.lan").waitForExistence(timeout: 15), "first alert never showed")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(alertNaming("first.lan").exists, "the second host replaced the first")
        app.alerts.buttons["cancel"].tap()

        XCTAssertTrue(alertNaming("second.lan").waitForExistence(timeout: 10), "second alert never showed")
        app.alerts.buttons["cancel"].tap()

        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.alerts.firstMatch.exists, "an answered alert came back")
    }

    /// A change reported while the link-a-device sheet is up must still reach the user: a sheet
    /// covers alert attachments below it, so the sheet's own copy — bound to the same state —
    /// shows it, and answering settles both copies at once. No per-surface flags coordinate this.
    @MainActor
    func testAlertReachesTheUserOverThePairingSheet() throws {
        app.launchArguments = ["-kima-fake-cert-changed", "pair.lan"]
        launchIntoConnectScreen(app)

        app.open(URL(string: "kima://link?code=ABC234&server=https%3A%2F%2Fkima.example.com")!)
        XCTAssertTrue(app.buttons["link device"].waitForExistence(timeout: 20), "pairing sheet never showed")

        // The hook reports ~3s after launch, so the sheet is up before the change lands.
        XCTAssertTrue(alertNaming("pair.lan").waitForExistence(timeout: 15), "no alert over the pairing sheet")

        app.alerts.buttons["cancel"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5), "the alert survived its answer")
        XCTAssertTrue(app.buttons["link device"].exists, "answering the alert broke the sheet underneath")
        app.buttons["close"].tap()
    }
}
