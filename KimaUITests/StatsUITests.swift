import XCTest

/// The stats page (1.11 web parity), run against the simulator's saved session on any account. Checks that real
/// figures render and that the hour drill and the false-starts audit work; a part skips when the account has no data
/// for it.
final class StatsUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testStatsPageRendersAndDrillsWork() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-kima-open", "stats"]
        app.launch()

        // The period control is Buttons, not staticTexts (SwiftUI merges the
        // label into the button element — confirmed via run-3 AX dump).
        XCTAssertTrue(button(app, "30 days").waitForExistence(timeout: 20),
                      "period control never rendered: \(app.debugDescription.prefix(6000))")
        XCTAssertTrue(text(app, contains: "hours of music").waitForExistence(timeout: 30),
                      "hero sentence never rendered")
        attachScreenshot("stats-overview")
        // Evidence first: a failure below must leave a screenshot behind
        // (continueAfterFailure=false aborts before any later attach).
        XCTAssertTrue(text(app, contains: "plays").waitForExistence(timeout: 15),
                      "exact counts missing")

        // Rhythm grid → hour drill; the grid sits ~1500pt down a lazy page. Loop on isHittable, NOT
        // exists: in a LazyVStack `.exists` is true for off-screen rendered cells and `.tap()` lands on
        // whatever occupies the content-space point. Only hours with plays are buttons (the drill opens
        // only for those), so the first clock button is a cell that opens, on any account.
        let cell = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "clock-")).firstMatch
        for _ in 0..<12 where !cell.isHittable {
            safeSwipeUp(app)
            _ = cell.waitForExistence(timeout: 2)
        }
        if !cell.exists {
            attachScreenshot("stats-no-clock-plays")
            throw XCTSkip("no hour of the week has plays on this account, so no drill opens")
        }
        XCTAssertTrue(cell.isHittable, "clock cell on screen but not hittable")
        cell.tap()
        // The sheet's done button is the one element reliably exposed to accessibility, so
        // the test waits on it to know the sheet is open.
        let done = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", "done", "hour-drill-done")).firstMatch
        if !done.waitForExistence(timeout: 20) {
            attachScreenshot("sheet-open-fail")
            XCTFail("hour sheet never opened: \(app.debugDescription.prefix(9000))")
        }
        XCTAssertTrue(text(app, contains: "plays").waitForExistence(timeout: 15),
                      "hour sheet has no count")
        attachScreenshot("stats-hour-drill")
        if done.isHittable {
            done.tap()
        } else {
            // Chrome-invariant fallback: drag the sheet down from its top area.
            let sheetFrom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            let sheetTo = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
            sheetFrom.press(forDuration: 0.05, thenDragTo: sheetTo)
            sheetFrom.press(forDuration: 0.05, thenDragTo: sheetTo)
        }
        XCTAssertTrue(done.waitForNonExistence(timeout: 8), "hour sheet never dismissed")
    }

    /// The false-starts audit: the scan is a read; merge must ask first, and the test cancels. Skips when the
    /// account has no duplicate rows to merge (the merge button only shows when there are some).
    @MainActor
    func testFalseStartsMergeAsksFirst() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-kima-open", "stats"]
        app.launch()
        XCTAssertTrue(button(app, "30 days").waitForExistence(timeout: 20), "period control never rendered")

        // The audit chapter sits at the bottom of a long page (lazy stack) —
        // scroll until its run button is HITTABLE (see the clock-cell note).
        let scroller = app.scrollViews.firstMatch
        let runButton = app.buttons["audit-scan"]
        for _ in 0..<20 where !runButton.isHittable {
            safeSwipeUp(scroller)
            _ = runButton.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(runButton.waitForExistence(timeout: 10), "audit intro never scrolled into view")
        XCTAssertTrue(runButton.isHittable, "audit run button visible but not hittable")
        attachScreenshot("stats-false-starts-intro")
        runButton.tap()
        // "total plays" heads every finished scan; the merge button follows only when there are duplicates.
        XCTAssertTrue(text(app, contains: "total plays").waitForExistence(timeout: 120), "audit never finished")
        let merge = app.buttons["audit-merge"]
        if !merge.waitForExistence(timeout: 3) {
            attachScreenshot("stats-false-starts-no-duplicates")
            throw XCTSkip("the scan found no duplicate rows on this account, so there is no merge to confirm")
        }
        // Results render below the fold of the audit section — same rule:
        // exists is not hittable; scroll, don't assert.
        for _ in 0..<6 where !merge.isHittable {
            safeSwipeUp(scroller)
        }
        XCTAssertTrue(merge.isHittable, "merge button rendered off the viewport")
        attachScreenshot("stats-false-starts-results")

        // Merge routes through the root-hosted confirmation sheet (merge / cancel). Prove the gate, then cancel.
        merge.tap()
        let confirm = app.buttons["stats-confirm-destructive"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10),
                      "merge had no confirmation step: \(app.debugDescription.prefix(4000))")
        attachScreenshot("stats-merge-confirm")
        // Coordinate tap: an element tap first issues the ScrollToVisible AX
        // action, which a sheet-hosted button refuses (kAXErrorCannotComplete,
        // run 22 — the button IS on screen). Coordinates skip that action.
        let cancelBtn = app.buttons["stats-confirm-cancel"]
        XCTAssertTrue(cancelBtn.waitForExistence(timeout: 10), "confirm sheet has no cancel")
        cancelBtn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 8), "confirm sheet never dismissed")
    }

    /// Scrolls the page until `element` is on screen (isHittable, not exists —
    /// see the clock-cell note above), at most 20 swipes.
    @MainActor private func scrollTo(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<20 where !element.isHittable {
            safeSwipeUp(app)
            _ = element.waitForExistence(timeout: 2)
        }
    }

    /// Tapping the C major wedge (top of the outer ring) selects it and the
    /// caption under the wheel names it. Read-only: the play button is never tapped.
    @MainActor
    func testKeyWheelTapShowsCount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-kima-open", "stats"]
        app.launch()
        let wheel = app.descendants(matching: .any)["key-wheel"]
        _ = wheel.waitForExistence(timeout: 30)
        scrollTo(wheel, app)
        XCTAssertTrue(wheel.isHittable, "key wheel never scrolled into view")
        wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1075)).tap()
        let caption = app.staticTexts["key-wheel-caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "key wheel caption missing")
        let shown = NSPredicate(format: "label CONTAINS[c] %@", "c major")
        expectation(for: shown, evaluatedWith: caption)
        waitForExpectations(timeout: 5)
        attachScreenshot("stats-key-wheel")
    }

    /// A busiest-hour row opens the same hour sheet as a grid cell.
    @MainActor
    func testBusiestHourRowOpensSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-kima-open", "stats"]
        app.launch()
        let row = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "busiest-hour-")).firstMatch
        _ = row.waitForExistence(timeout: 30)
        scrollTo(row, app)
        XCTAssertTrue(row.isHittable, "busiest hour row never scrolled into view")
        row.tap()
        let done = app.buttons["hour-drill-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 20), "hour sheet never opened from a busiest-hour row")
        attachScreenshot("stats-busiest-hour-sheet")
        if done.isHittable {
            done.tap()
        } else {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
            from.press(forDuration: 0.05, thenDragTo: to)
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        XCTAssertTrue(done.waitForNonExistence(timeout: 8), "hour sheet never dismissed")
    }

    /// Screenshots for review, in page order: shape, energy by hour, decades. Each sits down a lazy page and exists
    /// only once scrolled near, so scroll first, then check. The decades plot needs albums from two decades.
    @MainActor
    func testSectionsRender() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-kima-open", "stats"]
        app.launch()
        XCTAssertTrue(button(app, "30 days").waitForExistence(timeout: 20), "period control never rendered")
        for (id, shot) in [("shape-plot", "stats-shape"), ("energy-chart", "stats-energy"), ("decades-plot", "stats-decades")] {
            let el = app.descendants(matching: .any)[id]
            _ = el.waitForExistence(timeout: 5)
            scrollTo(el, app)
            XCTAssertTrue(el.waitForExistence(timeout: 5), "\(id) never rendered")
            attachScreenshot(shot)
        }
    }

    private func button(_ app: XCUIApplication, _ needle: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", needle, needle)).firstMatch
    }
}
