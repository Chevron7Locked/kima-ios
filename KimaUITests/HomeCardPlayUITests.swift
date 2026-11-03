import XCTest

/// The home screen's fetch-backed plays: a mix card fetches GET /mixes/:id and a
/// continue-listening card fetches the item's detail, both on the user's server. Before this the
/// mix card had no play affordance at all and the continue badges never spun, so a tap looked
/// ignored. `-kima-card-play-delay` pads those fetches in DEBUG (Kima/Core/DebugCardPlayDelay.swift)
/// so the in-flight window is long enough to assert.
class HomeCardPlayUITests: XCTestCase {

    @MainActor
    func testMixCardPlayShowsLoadingThenPlays() throws {
        let app = XCUIApplication()
        // `-kima-no-whatsnew` keeps the whats-new gate (a full-screen sheet over the home feed,
        // server-pending per release) from covering the rail card this test taps.
        app.launchArguments = ["-kima-tab", "0", "-kima-card-play-delay", "2500", "-kima-no-whatsnew"]
        app.launch()

        let card = app.buttons.matching(NSPredicate(format: "identifier == %@", "mix-card")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 40), "no made-for-you mix card on home")
        XCTAssertTrue(card.scrollToFullyVisible(in: app),
                      "the mix card never scrolled fully into view")

        // The card's artwork opens the mix (label: the cover's alt text); the mini player's label
        // names the playing track and artist.
        let mixName = card.label.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        XCTAssertFalse(mixName.isEmpty, "the mix card has no readable name (\(card.label))")

        card.tap()
        let busy = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS[c] %@", "play-badge", "loading")).firstMatch
        // 12s, not 3s: home boots heavy (the vibe map is a 5 MB decode) and the app's own log shows
        // the tap's action firing 4.5-7s after a synthesized touch. The busy window (2.5s,
        // `-kima-card-play-delay`) opens only when playMix starts, so the probe window must reach
        // past the dispatch — a 3s window closes before the spinner is ever on screen.
        XCTAssertTrue(busy.waitForExistence(timeout: 12),
                      "the mix card gave no feedback while its tracks were being fetched")

        XCTAssertTrue(busy.waitForNonExistence(timeout: 25),
                      "the mix card stayed in its loading state — the play never completed")
        XCTAssertTrue(app.buttons["expand-player"].waitForExistence(timeout: 20),
                      "no mini player after the mix play")
    }

    @MainActor
    func testContinueListeningBadgeSpinsWhileTheItemIsFetched() throws {
        let app = XCUIApplication()
        // `-kima-no-whatsnew`: see the note in the mix test.
        app.launchArguments = ["-kima-tab", "0", "-kima-card-play-delay", "2500", "-kima-no-whatsnew"]
        app.launch()

        // The rail cards carry the "play <title>" accessibility label; the spotlight card says
        // "play"/"resume" plus the title, so match on the prefix.
        // The continue cards label their badges "play <title>" / "resume <title>"; the mix card's
        // badge is labelled just "play", so the trailing space keeps this test on the rail it means.
        let badge = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND (label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@)",
            "play-badge", "play ", "resume ")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 40), "no continue-listening play badge on home")
        XCTAssertTrue(badge.scrollToFullyVisible(in: app),
                      "the continue-listening badge never scrolled fully into view")
        let itemTitle = badge.label.replacingOccurrences(
            of: "^(play|resume) ", with: "", options: .regularExpression)
        badge.tap()
        let busy = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS[c] %@", "play-badge", "loading")).firstMatch
        XCTAssertTrue(busy.waitForExistence(timeout: 3),
                      "the continue-listening badge gave no feedback while the item was being fetched "
                      + "(label stayed \(badge.label))")
        XCTAssertTrue(busy.label.localizedCaseInsensitiveContains(itemTitle),
                      "the loading badge is not the tapped item (\(busy.label), tapped \(badge.label))")
        XCTAssertTrue(busy.waitForNonExistence(timeout: 25),
                      "the continue-listening badge stayed in its loading state")
        XCTAssertTrue(app.buttons["expand-player"].waitForExistence(timeout: 20),
                      "no mini player after the continue-listening play")
    }
}
