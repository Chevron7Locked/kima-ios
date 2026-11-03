import XCTest

/// The report sheet with no server (`-kima-fake-signed-in`): the "sent to github" card holds the note but not the
/// server address, "open on github" shows the GitHub page in the in-app browser, and closing that browser closes the
/// sheet with a copy saved on the phone. The test never touches the GitHub page, so nothing is submitted.
final class IssueReportUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testOpenOnGitHubShowsThePageAndClosingItSavesACopy() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-kima-fake-signed-in", "-kima-open", "report"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["issue-report-sheet"].firstMatch.waitForExistence(timeout: 30),
                      "report sheet never opened")

        let note = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'what happened' AND (elementType == %d OR elementType == %d)",
                        XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue)
        ).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "note field missing")
        note.tap()
        note.typeText("ui test note: queue skipped")

        let card = app.descendants(matching: .any)["issue-report-github-fields"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "sent to github card missing")
        XCTAssertTrue(card.label.contains("ui test note: queue skipped"), "card does not show the note: \(card.label)")
        XCTAssertFalse(card.label.contains("127.0.0.1"), "card shows the server address: \(card.label)")
        attachScreenshot("report-sheet")

        let open = app.buttons["open on github"]
        if !open.isHittable { safeSwipeUp(app) }
        open.tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), "in-app browser never showed")
        RunLoop.main.run(until: Date().addingTimeInterval(4))
        attachScreenshot("report-github-page")
        close.tap()

        XCTAssertTrue(text(app, contains: "copy saved on phone").waitForExistence(timeout: 8), "no saved toast")
        XCTAssertFalse(app.descendants(matching: .any)["issue-report-sheet"].firstMatch.exists,
                       "report sheet still open after the browser closed")
    }
}
