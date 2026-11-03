import XCTest

/// The real replace question (Kima's own prompt), driven by the `-kima-vibe-fake-replace…` hooks (a fake song-path
/// queue, then a request to replace it with a play-similar queue). No server, no playback.
final class VibeReplaceUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() { continueAfterFailure = false }

    override func tearDown() { app.terminate() }

    private func launch(_ hook: String) {
        app.launchArguments = ["-kima-fake-signed-in", "-kima-fake-now-playing", hook]
        app.launch()
    }

    /// What is playing, as seen from the full player and from the shell.
    private var marker: XCUIElement { app.staticTexts["vibe-fake-replace-origin"] }
    private var shellMarker: XCUIElement { app.staticTexts["vibe-fake-replace-origin-shell"] }
    private var replaceButtons: XCUIElementQuery { app.buttons.matching(NSPredicate(format: "label == 'replace'")) }

    private func waitForDialog() {
        XCTAssertTrue(marker.waitForExistence(timeout: 30), "full player never opened")
        XCTAssertEqual(marker.label, "song path")
        XCTAssertTrue(app.buttons["replace"].waitForExistence(timeout: 15), "replace prompt never appeared")
        XCTAssertTrue(app.staticTexts["replace the song path with similar tracks?"].exists)
        XCTAssertTrue(app.buttons["keep"].exists)
    }

    private func expectOrigin(_ name: String, on element: XCUIElement) {
        expectation(for: NSPredicate(format: "label == %@", name), evaluatedWith: element)
        waitForExpectations(timeout: 10)
    }

    @MainActor
    func testReplaceProceeds() throws {
        launch("-kima-vibe-fake-replace")
        waitForDialog()
        app.buttons["replace"].tap()
        expectOrigin("play similar", on: marker)
        XCTAssertFalse(app.buttons["replace"].exists)
    }

    @MainActor
    func testCancelChangesNothing() throws {
        launch("-kima-vibe-fake-replace")
        waitForDialog()
        app.buttons["keep"].tap()
        XCTAssertTrue(app.buttons["replace"].waitForNonExistence(timeout: 10))
        // Give a wrongly-proceeding answer time to land before checking.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(marker.label, "song path")
    }

    /// Tapping the dimmed screen around the prompt keeps the queue too.
    @MainActor
    func testTappingOutsideKeeps() throws {
        launch("-kima-vibe-fake-replace")
        waitForDialog()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(app.buttons["replace"].waitForNonExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(marker.label, "song path")
    }

    /// With no cover open (the mini player's vibe button), the shell asks.
    @MainActor
    func testShellAsksWhenNoCoverIsOpen() throws {
        launch("-kima-vibe-fake-replace-shell")
        XCTAssertTrue(shellMarker.waitForExistence(timeout: 30), "shell never loaded")
        XCTAssertEqual(shellMarker.label, "song path")
        XCTAssertTrue(app.buttons["replace"].waitForExistence(timeout: 15), "the shell never asked")
        XCTAssertTrue(app.staticTexts["replace the song path with similar tracks?"].exists)
        XCTAssertEqual(replaceButtons.count, 1)
        app.buttons["replace"].tap()
        expectOrigin("play similar", on: shellMarker)
        XCTAssertFalse(app.buttons["replace"].waitForExistence(timeout: 2), "asked a second time")
    }

    /// The full player opens while the shell is asking. The question must not show twice, and it must
    /// never stay open with no dialog on screen.
    @MainActor
    func testOpeningThePlayerWhileAskingNeverShowsTwiceOrHangs() throws {
        launch("-kima-vibe-fake-replace-handoff")
        XCTAssertTrue(app.buttons["replace"].waitForExistence(timeout: 30), "the shell never asked")
        XCTAssertTrue(marker.waitForExistence(timeout: 15), "full player never opened")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertLessThanOrEqual(replaceButtons.count, 1, "shown twice")
        let outcome = app.staticTexts["vibe-fake-replace-origin-asking"].label
        XCTContext.runActivity(named: "hand-off: \(outcome)") { _ in }
        if outcome == "asking" {
            XCTAssertTrue(app.buttons["replace"].waitForExistence(timeout: 5), "question open with no dialog")
            app.buttons["replace"].tap()
            expectOrigin("play similar", on: marker)
        } else {
            XCTAssertEqual(marker.label, "song path")
        }
    }
}
