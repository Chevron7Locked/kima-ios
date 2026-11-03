import XCTest

/// Podcast detail paging against real server data. Launches with the DEBUG deep link (`-kima-open podcast`), which
/// selects the Podcasts tab and pushes the first subscribed show. The simulator must already have a saved session; the
/// test skips with an explanation when the app boots to onboarding instead.
final class PodcastPagingUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testPodcastDetailShowsPagedEpisodesAndSortControl() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-kima-open", "podcast"]
        app.launch()

        // Deep-link pushed a detail screen: episodes header + sort control must appear.
        // (Header is "episodes <count>" — match by prefix.)
        let episodesHeader = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'episodes'")
        ).firstMatch
        XCTAssertTrue(
            episodesHeader.waitForExistence(timeout: 30),
            "Podcast detail never showed the Episodes section (onboarding state or network failure?)"
        )

        // The sort control (Newest First / Oldest First toggle).
        let sortControl = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'first' OR label CONTAINS[c] 'Newest' OR label CONTAINS[c] 'Oldest'")
        ).firstMatch
        XCTAssertTrue(sortControl.waitForExistence(timeout: 10),
                      "Episode sort control missing on podcast detail")

        // At least a handful of episode rows rendered (server page came back).
        let playButtons = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'play episode' OR label CONTAINS[c] 'play'")
        )
        XCTAssertGreaterThanOrEqual(playButtons.count, 3,
                                    "Episode rows did not render from the paged API")

        // Infinite-scroll trigger sits 5 rows from the bottom of the accumulator; scrolling the
        // list should not crash and keeps content stable (loadMore is serialized in the VM).
        // NOTE: the LazyVStack unmounts off-screen rows (including the header), so assert on
        // episode rows still being present rather than on the scrolled-away header.
        safeSwipeUp(app)
        safeSwipeUp(app)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App crashed or backgrounded while scrolling")
        XCTAssertGreaterThanOrEqual(playButtons.count, 3,
                                    "Episode rows disappeared after scrolling (paging regression?)")
    }
}
