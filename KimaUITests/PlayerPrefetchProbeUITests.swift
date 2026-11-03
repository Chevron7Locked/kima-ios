import XCTest

/// Measurement harness for the "stops between songs" gap: plays podcasts via the DEBUG deep link, taps "Next", and
/// a ready line with prefetch=1 proves the handoff. Read the numbers host-side after the run:
///   xcrun simctl spawn booted log show --last 2m \
///     --predicate 'subsystem == "com.chevron7locked.kima"' --style compact | rg KIMA_AUDIO
/// Playing saves each episode's place on the server, so setUp saves the first podcast's places through the app's
/// DEBUG hook and tearDown puts them back, also after a failure. It plays unplayed episodes, whose added places are
/// removed exactly; an episode that had a place gets it back with a new last-played time.
final class PlayerPrefetchProbeUITests: XCTestCase {
    private var saved = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        let line = serverState("snapshot", "podcast-progress")
        guard line.hasPrefix("saved:") else {
            throw XCTSkip("episode places not saved first, so nothing played: \(line)")
        }
        saved = true
    }

    override func tearDown() {
        XCUIApplication().terminate()
        guard saved else { return }
        let line = serverState("restore", "podcast-progress")
        XCTAssertTrue(line.hasPrefix("restored:"), "episode places not put back: \(line)")
    }

    @MainActor
    func testPlaybackStartFiresGapProbeAndPrefetch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-kima-open", "podcast"]
        app.launch()

        // Only episodes with no saved place: removing what the test adds leaves them exactly as they were.
        let unplayed = app.buttons["show unplayed episodes"]
        XCTAssertTrue(unplayed.waitForExistence(timeout: 30), "episode filters missing (no session or network?)")
        for _ in 0..<4 where !unplayed.isHittable { safeSwipeUp(app) }
        XCTAssertTrue(unplayed.isHittable, "unplayed filter not hittable")
        unplayed.tap()

        let playButtons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'play episode '"))
        guard playButtons.firstMatch.waitForExistence(timeout: 10) else {
            throw XCTSkip("the first podcast has no unplayed episodes")
        }

        // Some episodes are video/no-audio and never start the engine — try up to 3 rows,
        // and only accept a REAL playback signal: the transport pause button (the engine
        // flipped to playing), not just "any button exists".
        let pause = app.buttons["pause"]
        var engaged = false
        for i in 0..<min(3, playButtons.count) {
            playButtons.element(boundBy: i).tap()
            engaged = pause.waitForExistence(timeout: 15)
            if engaged { break }
        }
        XCTAssertTrue(engaged, "No episode row produced actual playback (Pause button never appeared)")

        // Let prefetch settle (it fires at current-track ready: mint + warm the next URL).
        usleep(2_000_000)

        // Expand to the full player and press Next: the advance must land on the WARMED
        // prefetch asset (engine logs `ready ... prefetch=1` — read host-side after the run).
        // The element carries .isButton, so the accessibility engine indexes it as a button.
        let expand = app.buttons["expand-player"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10),
                      "Mini-player expand hook not found — cannot drive the warm advance")
        expand.tap()

        // Lowercase: PlayerTransportControls labels the button "next" (a293520 sweep).
        let next = app.buttons["next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Full-player Next button missing")
        next.tap()
        // New item (cold or warm) loads; give the engine room to log its ready probe.
        usleep(6_000_000)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
