import XCTest

extension XCTestCase {
    /// Launches straight onto the connect screen, whatever login the simulator holds:
    /// `-kima-fake-signed-out` starts this process signed out and leaves the stored server and
    /// credential alone. Returns with "scan qr code", the pairing entry point, on screen.
    func launchIntoConnectScreen(_ app: XCUIApplication) {
        app.launchArguments += ["-kima-fake-signed-out"]
        app.launch()
        XCTAssertTrue(app.buttons["scan qr code"].waitForExistence(timeout: 30), "connect screen never showed")
    }
}
