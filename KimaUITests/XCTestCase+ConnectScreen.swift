import XCTest

extension XCTestCase {
    /// Launches and lands on the connect screen from any start: a simulator that remembers an
    /// unreachable server lands on the can't-reach gate first; this leaves it for the connect
    /// screen without touching any stored login. Assumes a signed-out simulator, so "scan qr
    /// code" — the pairing entry point — is on screen when this returns.
    func launchIntoConnectScreen(_ app: XCUIApplication) {
        app.launch()
        let change = app.buttons["change server address"]
        if change.waitForExistence(timeout: 20) { change.tap() }
        XCTAssertTrue(app.buttons["scan qr code"].waitForExistence(timeout: 30), "connect screen never showed")
    }
}
