import XCTest

/// Real-touch taps on the shell's bell and on the More tab's "report a problem" row. (On iOS 26 a
/// glassEffect on a button's label swallowed the touch.) Taps here are by COORDINATE (a real touch at the
/// element's centre); element-level `.tap()` can succeed through accessibility even when a real
/// touch is swallowed. Needs no server or credential: `-kima-fake-signed-in` (DEBUG hook).
final class BellTapUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchShell(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-kima-fake-signed-in", "-kima-fake-unread", "3"] + extra
        app.launch()
        return app
    }

    private func tapByCoordinate(_ app: XCUIApplication, _ element: XCUIElement) {
        let frame = element.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .tap()
    }

    @MainActor
    func testBellOpensActivitySheetOnRealTouch() throws {
        let app = launchShell()
        let bell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'activity'")).firstMatch
        XCTAssertTrue(bell.waitForExistence(timeout: 30), "bell button missing from the shell")
        tapByCoordinate(app, bell)
        XCTAssertTrue(app.descendants(matching: .any)["activity-sheet-header"].waitForExistence(timeout: 8),
                      "activity sheet did not open after a coordinate tap on the bell")
    }

    @MainActor
    func testMoreReportRowOpensReportSheetOnRealTouch() throws {
        let app = launchShell(["-kima-tab", "4"])
        let report = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'report a problem'")).firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 30), "report row missing from the more tab")
        // The row closes the menu, below the fold: scroll to the end before a coordinate tap.
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(report.isHittable, "report row is off-screen after scrolling the more tab")
        tapByCoordinate(app, report)
        XCTAssertTrue(app.descendants(matching: .any)["issue-report-sheet"].firstMatch.waitForExistence(timeout: 8),
                      "report sheet did not open after a coordinate tap on the more tab's report row")
    }
}
