import XCTest

/// Two servers' certificates change at once: the first alert stays until answered, then the
/// second one shows. Driven by the `-kima-fake-cert-changed` hook; no server.
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
}
