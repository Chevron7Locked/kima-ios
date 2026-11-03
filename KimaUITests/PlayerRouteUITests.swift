import XCTest

/// Sleep-timer end-of-item policies + player deep-link routes. Routes go through the same PlayerRoute queue the kima://
/// URL scheme uses (XCUITest can't reliably drive open→background→reopen; the debug launch arg feeds the same queue).
/// Not covered: pause-at-item-end itself (needs a natural item end) and real `kima://` delivery from another app.
final class PlayerRouteUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// kima://sleep-timer route opens the sleep sheet; arming "End of Track" sets the
    /// policy, dismisses the sheet, and the trigger button re-badges to show it armed.
    @MainActor
    func testSleepTimerRouteOpensSheetAndArmsEndOfTrack() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-kima-open", "sleep-timer"]
        app.launch()

        let sheet = app.otherElements["sleep-timer-route-sheet"]
        // The route is delivered after the shell's first task settles; give the auth
        // + shell path the same generous budget the paging tests use.
        XCTAssertTrue(sheet.waitForExistence(timeout: 30),
                      "kima://sleep-timer route did not present the sleep sheet")

        // NOTE (probe-verified): the sheet root's accessibilityIdentifier propagates
        // onto flattened sheet descendants, shadowing their own ids — query BY LABEL.
        // AND: waitForExistence on a query NESTED under a container that exists but is
        // still mounting returns false without retrying the child — query at app scope.
        let trackRow = app.buttons["end of track"]
        XCTAssertTrue(trackRow.waitForExistence(timeout: 12),
                      "End of Track policy row missing from the sheet")
        trackRow.tap()

        // Arming dismisses the sheet (same contract as the minute presets).
        let goneExpectation = expectation(for: NSPredicate(format: "exists == 0"),
                                          evaluatedWith: sheet)
        wait(for: [goneExpectation], timeout: 8)

        // The route path has no trigger button in view (the full player is not opened
        // by this arg) — the armed state lives on the shared model; its badge is
        // asserted in testSleepPolicyBadgeInFullPlayer below.
    }

    /// With the full player up, the sleep-timer trigger is reachable and the policy
    /// badge appears after arming ("After Track"). This drives the player-internal
    /// delivery path's counterpart: the same sheet content from the button side.
    @MainActor
    func testSleepPolicyBadgeInFullPlayer() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-kima-open-player"]
        app.launch()

        // The full player hosts the secondary controls row; the sleep button is
        // labelled for a11y from its model state ("Set sleep timer" when idle).
        let sleepButton = app.buttons["sleep-timer-button"]
        XCTAssertTrue(sleepButton.waitForExistence(timeout: 30),
                      "Sleep timer button missing from the full player")
        sleepButton.tap()

        let trackRow = app.buttons["end of track"]
        XCTAssertTrue(trackRow.waitForExistence(timeout: 5),
                      "End of Track policy row missing (button-opened sheet)")
        trackRow.tap()

        // Badge flips from "Set sleep timer" to the armed label once dismissed.
        // Armed label is "sleep timer: end of track" (SleepTimerSheet.swift:161, lowercase).
        let armed = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'sleep timer: end of track'")
        ).firstMatch
        XCTAssertTrue(armed.waitForExistence(timeout: 8),
                      "Trigger did not re-badge after arming End of Track")
    }

    /// kima://queue with a truly idle player must not spawn an empty sheet over the tabs or crash the shell. A session
    /// that hydrates late legitimately opens the sheet when it appears, so the test asserts the invariant
    /// (mini-player present ⇒ route sheet present) rather than a fixed outcome.
    @MainActor
    func testQueueRouteIsSafeWhenIdle() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-kima-open", "queue"]
        app.launch()

        let routeSheet = app.staticTexts["queue-sheet-up-next"]   // content-placed marker (QueueSheet header; resolves as staticText — probe-verified)
        let miniPlayer = app.buttons["expand-player"]

        // Wait for the first sign of a session (hydration) — up to 25 s.
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline, !miniPlayer.exists, !routeSheet.exists {
            Thread.sleep(forTimeInterval: 0.5)
        }

        if miniPlayer.exists {
            // A session exists ⇒ the route must have opened the queue sheet. The full
            // player is never auto-opened by this arg, so the marker can only come from
            // the route sheet (the player's own queue sheet would need a tap to open).
            XCTAssertTrue(routeSheet.waitForExistence(timeout: 10),
                          "Session active but kima://queue opened nothing")
        } else {
            // Still fully idle ⇒ no sheet now. (If hydration lands AFTER this point the
            // route legitimately delivers then — unobservable by this test by design.)
            XCTAssertFalse(routeSheet.exists,
                           "Empty-queue session must not present the queue sheet")
        }
    }
}
