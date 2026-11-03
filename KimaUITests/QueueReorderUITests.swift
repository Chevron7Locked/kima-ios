import XCTest

/// Reordering the queue by a row's handle, with a placeholder queue (`-kima-fake-queue`) that is never saved to the
/// server, so it runs signed out or on a real phone without touching the account's queue.
final class QueueReorderUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() { continueAfterFailure = false }

    override func tearDown() { app.terminate() }

    private func openQueue(tracks: Int) {
        app.launchArguments = ["-kima-fake-signed-in", "-kima-no-whatsnew", "-kima-fake-queue", "\(tracks)",
                               "-kima-open", "queue"]
        app.launch()
        XCTAssertTrue(app.staticTexts["queue-sheet-up-next"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["queued 2"].waitForExistence(timeout: 5))
    }

    /// The reorder handle at the trailing edge of the row titled `title`.
    private func handle(of title: String) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.maxX - 30, dy: app.staticTexts[title].firstMatch.frame.midY + 8))
    }

    private func y(_ title: String) -> CGFloat { app.staticTexts[title].firstMatch.frame.minY }

    /// Short queue (rows built at once): drag a track two places down; taps on rows do nothing while editing.
    func testDragHandleMovesTrack() throws {
        openQueue(tracks: 6)
        XCTAssertLessThan(y("queued 2"), y("queued 4"))

        app.buttons["edit"].tap()
        let step = y("queued 4") - y("queued 3")
        let start = handle(of: "queued 2")
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: step * 2)))

        let moved = expectation(for: NSPredicate { _, _ in self.y("queued 2") > self.y("queued 4") }, evaluatedWith: nil)
        wait(for: [moved], timeout: 5)
        XCTAssertLessThan(y("queued 2"), y("queued 5"))
        attachScreenshot("queue-after-drag")

        // Tapping a row while editing does not jump to it: the sheet stays open.
        app.staticTexts["queued 5"].tap()
        XCTAssertTrue(app.staticTexts["queue-sheet-up-next"].exists)
        app.buttons["done"].tap()
        XCTAssertTrue(app.buttons["edit"].waitForExistence(timeout: 3))
    }

    /// Long queue (over the 80 rows built at once outside editing): holding a track at the bottom edge scrolls the
    /// queue, and the track lands far below where it started.
    func testHoldAtEdgeScrollsAndMovesTrack() throws {
        openQueue(tracks: 120)
        app.buttons["edit"].tap()
        let start = handle(of: "queued 2")
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.94)).withOffset(CGVector(dx: app.frame.maxX - 30, dy: 0))
        start.press(forDuration: 0.3, thenDragTo: bottom, withVelocity: .default, thenHoldForDuration: 2.5)
        attachScreenshot("queue-after-edge-hold")

        // Track 2 now plays after tracks it started ahead of. ("queued 1" is not used: the mini player shows it too.)
        XCTAssertGreaterThan(y("queued 2"), y("queued 10"), "track 2 did not move down the queue")
        attachScreenshot("queue-after-edge-drop")
    }
}
