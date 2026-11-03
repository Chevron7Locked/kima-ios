import XCTest

/// Playing straight from a library card takes seconds on a slow server, so the tapped badge must
/// show its spinner (and stop accepting taps) for that whole window, then hand off to the mini
/// player. `-kima-card-play-delay` pads the fetch in DEBUG (Kima/Core/DebugCardPlayDelay.swift) so
/// the window is long enough to assert.
///
/// The assertion names the artist from the badge it taps, and waits for the mini player's label to
/// change to that artist. Both matter: the app restores the last played track on launch, so a mini
/// player that merely exists proves nothing about the tap, and the queue swap lands a beat after
/// the badge stops spinning — on the lean play-queue endpoint the whole fetch takes tens of
/// milliseconds, so a single snapshot of the mini player can still show the restored track.
class CardPlayFeedbackUITests: XCTestCase {

    @MainActor
    func testArtistCardPlayShowsLoadingThenPlays() throws {
        let app = XCUIApplication()
        // `-kima-no-whatsnew`: the whats-new gate is a full-screen sheet; with a release pending
        // for the account it covers the grid's "play <artist>" badges and every tap is
        // "not hittable". See DebugCardPlayDelay.swift.
        app.launchArguments = ["-kima-tab", "1", "-kima-card-play-delay", "2500", "-kima-no-whatsnew"]
        app.launch()

        // The app restores the last played track, and that chrome sits over the bottom of the grid:
        // a badge can be fully on screen and still be covered, and the tap then lands on the player
        // (which expands it) instead of the badge. See XCUIElement+SafeSwipe.swift, whose helper
        // this is — the suites that tap near the bottom of a scroll view all need it.
        collapsePlayerOverlays(app)

        // State restoration can leave the Collection stack at its last artist page; back to the grid.
        for _ in 0..<4 {
            let back = app.buttons["BackButton"]
            guard back.waitForExistence(timeout: 2) else { break }
            back.tap()
            sleep(1)
        }
        let artistsTab = app.buttons.matching(NSPredicate(format: "label == %@", "artists")).firstMatch
        XCTAssertTrue(artistsTab.waitForExistence(timeout: 20), "collection toolbar never rendered")
        artistsTab.tap()

        // A grid badge reads "play <artist>"; the busy state replaces that with "loading <artist>".
        let badge = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label BEGINSWITH[c] %@", "play-badge", "play ")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 40), "no named artist play badge in the grid")
        // Scroll by frame: isHittable is true for a badge whose centre is below the fold, and the
        // tap then lands on nothing.
        XCTAssertTrue(badge.scrollToFullyVisible(in: app),
                      "no play badge scrolled fully into the visible area")

        let cardLabel = badge.label
        let artistName = cardLabel.replacingOccurrences(
            of: "^play ", with: "", options: [.regularExpression, .caseInsensitive])
        XCTAssertFalse(artistName.trimmingCharacters(in: .whitespaces).isEmpty,
                       "the badge the test taps names no artist (label: \(cardLabel))")

        let miniPlayer = app.buttons["expand-player"]
        // A restored session whose player was left minimized shows the "restore player" tab, not
        // the mini bar — reading a non-existent element's label throws. The label is failure-report
        // colour only, so take it when present and say so when not.
        let restoredTrack = miniPlayer.exists ? miniPlayer.label : "no restored track"

        badge.tap()
        let busy = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS[c] %@", "play-badge", "loading")).firstMatch
        XCTAssertTrue(busy.waitForExistence(timeout: 3),
                      "the badge gave no feedback after the play tap (label stayed \(badge.label))")

        XCTAssertTrue(busy.waitForNonExistence(timeout: 25),
                      "the badge stayed in its loading state — the play never completed")
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 20),
                      "no mini player after the card play")

        // The mini player keeps showing the restored track until the tapped artist's queue takes
        // over, so poll for the artist's name instead of snapshotting once.
        let deadline = Date().addingTimeInterval(20)
        var label = miniPlayer.label
        while !label.localizedCaseInsensitiveContains(artistName) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            label = miniPlayer.label
        }
        XCTAssertTrue(label.localizedCaseInsensitiveContains(artistName),
                      "the mini player is not playing the tapped artist "
                      + "(restored \(restoredTrack), now \(label), card \(cardLabel))")
    }
}
