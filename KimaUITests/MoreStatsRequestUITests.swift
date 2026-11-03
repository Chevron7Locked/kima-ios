import XCTest

/// A stats request from outside More (the full player's stats button, what's new) while a More screen
/// is open: Stats goes on top of it, and back returns to that screen. No server.
final class MoreStatsRequestUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() { continueAfterFailure = false }

    override func tearDown() { app.terminate() }

    @MainActor
    func testStatsStacksOnSettingsAndBackReturnsToIt() throws {
        app.launchArguments = ["-kima-fake-signed-in", "-kima-open", "settings", "-kima-stats-request-after", "6"]
        app.launch()
        // A section only Settings has (the More menu also has a row named "settings").
        let settings = app.staticTexts["about"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20), "settings never opened")
        let stats = app.navigationBars["stats"]
        XCTAssertTrue(stats.waitForExistence(timeout: 20), "the stats request never opened stats")
        stats.buttons.firstMatch.tap()
        XCTAssertTrue(stats.waitForNonExistence(timeout: 5))
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "back went past settings")
    }
}
