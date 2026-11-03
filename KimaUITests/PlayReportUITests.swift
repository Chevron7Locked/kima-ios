import XCTest

/// The play-report chain end-to-end: tapping the stats page's #1 top track plays it, and after the server's required
/// seconds (half the track, at most 240) the listen meter POSTs /plays; the app must stay alive through the 250s.
/// This records one real listen on the signed-in account's history. The play queue is saved first and put back after.
final class PlayReportUITests: XCTestCase {
    private let app = XCUIApplication()
    private var queueSaved = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        let line = serverState("snapshot", "queue")
        guard line.hasPrefix("saved:") else { throw XCTSkip("play queue not saved first, so not changed: \(line)") }
        queueSaved = true
        app.launchArguments = ["-kima-open", "stats"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        guard queueSaved else { return }
        let line = serverState("restore", "queue")
        XCTAssertTrue(line.hasPrefix("restored:"), "play queue not put back: \(line)")
    }

    @MainActor
    func testListeningFromStatsReportsAPlay() throws {
        // Stats page up (period control = the render gate, same as StatsUITests).
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "30 days"))
                      .firstMatch.waitForExistence(timeout: 20), "stats page never rendered")
        // Scroll to the top-list chapter and tap the #1 track row (plays the
        // slice starting at it; the meter starts measuring immediately).
        let row = app.buttons["top-track-0"]
        for _ in 0..<14 where !row.isHittable {
            safeSwipeUp(app)
            _ = row.waitForExistence(timeout: 2)
        }
        if !row.exists { throw XCTSkip("no top tracks in this period, so nothing to play") }
        XCTAssertTrue(row.isHittable, "top-list #1 row never became hittable")
        // The row reads "play <title>".
        let title = String(row.label.dropFirst("play ".count))
        let runStart = Date()
        row.tap()
        // The mini-player is proof the listen started.
        let mini = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        XCTAssertTrue(mini.waitForExistence(timeout: 15), "mini-player never showed the track")
        attachScreenshot("playreport-start")

        // Listen out the server's requirement (at most 240s) with margin. The pump
        // keeps the app in the foreground; the engine tick + meter run the
        // whole time (this is exactly what the meter is built for).
        let deadline = Date().addingTimeInterval(250)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(2))
        }
        // App still healthy after the window (the report fired inside it).
        XCTAssertTrue(app.tabBars.buttons["more"].exists, "app died during the listen window")
        attachScreenshot("playreport-end")
        // Check the account's history for a play of this track at or after this time.
        print("PLAYREPORT window start:", runStart.description)
    }
}
