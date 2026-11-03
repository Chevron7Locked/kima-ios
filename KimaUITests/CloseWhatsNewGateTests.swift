import XCTest

/// Closes the whats-new gate for screenshot sweeps of the screens behind it. Taps the footer's Done (server-side
/// dismiss) and asserts the sheet is actually gone: tab bars exist behind the sheet, so a bare tab-bar assert passes
/// with the gate still showing. The sheet-only `whatsnew-done` button leaving the accessibility tree is the signal.
/// A queued next window presents its own sheet, so the drain loops (capped). No-op when no gate opens.
/// Done marks each release seen for the account for good, so this runs only against a seeded test account
/// (`TEST_RUNNER_KIMA_UITEST_SEEDED_ACCOUNT=1`) and skips otherwise.
final class CloseWhatsNewGateTests: XCTestCase {

    /// Waits until `element` leaves the tree (XCTest has no waitForNonExistence).
    private func waitForDisappear(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == 0"), evaluatedWith: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    @MainActor
    func testCloseGate() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KIMA_UITEST_SEEDED_ACCOUNT"] == "1",
                          "closing a live window marks that release seen for the account; seeded test accounts only")
        let app = XCUIApplication()
        app.launch()
        let done = app.buttons["whatsnew-done"]

        if done.waitForExistence(timeout: 20) {
            var drains = 0
            while done.exists && drains < 4 {
                done.tap()
                XCTAssertTrue(waitForDisappear(done, timeout: 20),
                              "whats-new sheet still up 20s after Done — gate did not close")
                drains += 1
                // A queued next window presents its own Done; give it 2s to surface.
                _ = done.waitForExistence(timeout: 2)
            }
        }
        XCTAssertFalse(done.exists, "whats-new sheet still up — the gate never closed")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15), "shell never appeared")
    }
}
