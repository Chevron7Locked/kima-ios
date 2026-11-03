import XCTest

/// Home "made for you" rail and the mood mixer button (v1 /mixes contract). Uses the
/// simulator's saved production session. It opens the mixer and checks the five mood tiles
/// exist, but NEVER taps a mood tile or any save action: saving overwrites the account's
/// single saved mood mix, which WhatsNewUITests depends on.
final class MixesUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testMixesRailAndMoodMixerRender() throws {
        let app = XCUIApplication()
        // `-kima-no-whatsnew`: the whats-new gate is a full-screen sheet; with a release pending
        // for the account it covers the home feed's top section, where the mood mixer button is,
        // and nothing scrolls into view. See DebugCardPlayDelay.swift.
        app.launchArguments = ["-kima-no-whatsnew"]
        app.launch()

        // Scroll by frame, not isHittable: a partly-visible element reports hittable while its
        // centre sits below the fold, and the synthesised tap then lands on nothing.
        let mixer = app.buttons["mood-mixer-open"]
        XCTAssertTrue(mixer.waitForExistence(timeout: 20), "mood mixer button never rendered")
        XCTAssertTrue(mixer.scrollToFullyVisible(in: app),
                      "mood mixer button never scrolled fully into view")
        attachScreenshot("mixes-rail")

        XCTAssertGreaterThan(app.buttons.matching(identifier: "mix-card").count, 0,
                             "no mix cards in the made-for-you rail")
        let card = app.buttons.matching(identifier: "mix-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "first mix card never rendered")

        // The mood mixer is checked BEFORE any mix plays: once a mix plays, the floating mini player
        // covers the section header and takes the tap meant for the mood button.
        mixer.tap()
        for mood in ["happy", "party", "chill", "sad", "aggressive"] {
            XCTAssertTrue(app.buttons["mood-\(mood)"].waitForExistence(timeout: 20),
                          "mood tile \(mood) missing")
        }
        attachScreenshot("mood-mixer")
        // Deliberately no tap on a mood tile: that would save over the account's mood mix.
        app.buttons["moodmixer-close"].tap()
        sleep(1)

        // Re-query after the mixer round trip: the rail can reload behind the sheet, and an element
        // captured before it points at a frame that no longer holds the card. Tap inside the artwork,
        // above the title, so the point is on the card and on the screen.
        let target = app.buttons.matching(NSPredicate(format: "identifier == %@", "mix-card")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 20), "no mix card to tap after closing the mixer")
        XCTAssertTrue(target.scrollToFullyVisible(in: app),
                      "the mix card never scrolled fully into view before the tap")
        // Tap the play badge the user sees, scoped to this card; fall back to the card's middle. A
        // normalized-offset tap inside the horizontal rail can land on nothing.
        let badge = target.buttons.matching(NSPredicate(format: "identifier == %@", "play-badge")).firstMatch
        if badge.exists && badge.isHittable {
            badge.tap()
        } else {
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        print("MIXTAP badge=\(badge.exists && badge.isHittable) tabbar=\(app.tabBars.firstMatch.exists) "
              + "fullplayer=\(app.staticTexts.matching(NSPredicate(format: "label == %@", "now playing")).firstMatch.exists)")
        attachScreenshot("after-mix-tap")
        // The mini player appears the moment the queue commits, before the stream loads, so a few
        // seconds is the honest bound.
        XCTAssertTrue(app.buttons["expand-player"].waitForExistence(timeout: 5),
                      "mini-player never appeared after tapping a mix")
        // The bar names what is playing (measured: "Major Threat, Carpenter Brut" — the mix's first
        // track, not the mix's title). Naming the mix would be a product change, not a fact.
        let barLabel = app.buttons["expand-player"].label.trimmingCharacters(in: .whitespaces)
        XCTAssertFalse(barLabel.isEmpty, "the mini player appeared without naming what is playing")
        attachScreenshot("mix-playing")
    }
}
