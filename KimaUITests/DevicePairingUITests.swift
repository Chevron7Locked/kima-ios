import XCTest

/// The link-a-device sheet from a kima://link URL and from the "scan qr code" button. No server needed:
/// nothing here taps "link device", so no login is written. Starts signed out (`launchIntoConnectScreen`)
/// whatever the simulator holds.
final class DevicePairingUITests: XCTestCase {
    private let app = XCUIApplication()
    private let ok = "kima://link?code=ABC234&server=https%3A%2F%2Fkima.example.com"

    override func setUp() { continueAfterFailure = false }
    override func tearDown() { app.terminate() }

    @MainActor
    func testLinkShowsTheHostAndAskFirst() {
        launchIntoConnectScreen(app)
        savePairingShot("connect-screen")
        app.open(URL(string: ok)!)
        XCTAssertTrue(app.buttons["link device"].waitForExistence(timeout: 20))
        XCTAssertTrue(text(app, contains: "kima.example.com").exists)
        XCTAssertTrue(text(app, contains: "only link to a server you know.").exists)
        savePairingShot("pairing-confirm")
        app.buttons["close"].tap()
        XCTAssertTrue(app.buttons["link device"].waitForNonExistence(timeout: 10))
    }

    @MainActor
    func testLoopbackLinkOffersNoLinkButton() {
        launchIntoConnectScreen(app)
        app.open(URL(string: "kima://link?code=ABC234&server=http%3A%2F%2Flocalhost%3A3030")!)
        XCTAssertTrue(text(app, contains: "this code points at this computer").waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["link device"].exists)
        savePairingShot("pairing-loopback")
        app.buttons["close"].tap()
    }

    @MainActor
    func testMalformedLinkShowsAnError() {
        launchIntoConnectScreen(app)
        app.open(URL(string: "kima://link?code=ABC234")!)
        XCTAssertTrue(text(app, contains: "that isn't a valid kima link.").waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["link device"].exists)
        app.buttons["close"].tap()
    }

    @MainActor
    func testScanButtonOpensTheSheetAndSaysWhenTheDeviceCannotScan() {
        launchIntoConnectScreen(app)
        app.buttons["scan qr code"].tap()
        XCTAssertTrue(text(app, contains: "this device can't scan codes. type the code instead.").waitForExistence(timeout: 15))
        XCTAssertTrue(text(app, contains: "on the kima website, open settings → link a device.").exists)
        savePairingShot("pairing-scanner")
        app.buttons["close"].tap()
        XCTAssertTrue(app.buttons["scan qr code"].waitForExistence(timeout: 10))
    }
}
