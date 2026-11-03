import XCTest

/// Unowned popular tracks (`album.id = null`, a preview url) can only be previewed. Against the real server:
/// such a row is marked "preview", a tap starts the preview through the server's Deezer proxy (the row reads
/// "previewing", the mini player names the track), a second tap stops it. The printed mini-player line tells which
/// tier answered: Deezer gives a rank (1…10) as the play count, ListenBrainz sitewide listen counts.
class ArtistPreviewUITests: XCTestCase {

    @MainActor
    func testUnownedPopularRowPreviewsThroughTheServer() throws {
        // Measured on the live library: this artist has 101 albums, 1 owned, and 10 popularity
        // rows that are all unowned (see the card-play counts in docs/reviews notes).
        let app = XCUIApplication()
        app.launchArguments = ["-kima-tab", "1", "-kima-open", "artist", "cmsctl1r50906b2iqmbzu0t3m"]
        app.launch()

        let row = app.buttons["popular-row-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "no popularity rows on the artist page")
        XCTAssertTrue(row.label.contains("preview"), "the first popularity row is not a preview row: \(row.label)")
        if !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable, "the preview row is off-screen")

        row.tap()
        let previewing = NSPredicate(format: "label CONTAINS %@", "previewing")
        expectation(for: previewing, evaluatedWith: row)
        waitForExpectations(timeout: 20)

        let mini = app.buttons["expand-player"]
        XCTAssertTrue(mini.waitForExistence(timeout: 15), "no mini player during the preview")
        print("preview line: \(mini.label)")
        // Which tier answered is not observable from the UI: the row count is the tell
        // (Deezer sends its rank 1…10, ListenBrainz sends sitewide listen counts) and the
        // server logs it as `[Artist] Popular tracks from <source> (n)`.

        row.tap()
        expectation(for: NSPredicate(format: "NOT (label CONTAINS %@)", "previewing"), evaluatedWith: row)
        waitForExpectations(timeout: 15)
    }
}
