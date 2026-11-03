import XCTest

/// "Popular songs" on an artist page ranks by global popularity, with this user's own play counts as
/// the server's last tier; a global number reaches the row as a play count. A personal library's own counts are small integers; the
/// abbreviated formatter (Kima/Core/Extensions.swift) only emits "12K" / "1.5M" above 1,000, so a
/// K/M-scaled count on this page is the signature of a global number arriving in the app.
class ArtistPopularityUITests: XCTestCase {

    @MainActor
    func testArtistPageShowsGlobalPlayCounts() throws {
        let app = XCUIApplication()
        // The artist whose preview path is used in ArtistPreviewUITests: owned, unowned and
        // globally popular rows all present, so one page covers every row kind.
        app.launchArguments = ["-kima-tab", "1", "-kima-open", "artist", "cmsctl1r50906b2iqmbzu0t3m"]
        app.launch()

        let header = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "popular")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 40), "the popular section never rendered")
        for _ in 0..<8 {
            if header.isHittable { break }
            safeSwipeUp(app)
        }

        let counts = app.staticTexts.matching(NSPredicate(
            format: "label MATCHES[c] %@", "^[0-9]+(\\.[0-9]+)?[KM]$"))
        let values = counts.allElementsBoundByIndex.map(\.label)
        print("scaled play counts on the artist page: \(values)")
        XCTAssertGreaterThan(values.count, 0,
                             "no scaled play count on any popular row — the server's global "
                             + "popularity is not reaching the app (its last tier, local plays, "
                             + "renders as a plain small integer)")
    }
}
