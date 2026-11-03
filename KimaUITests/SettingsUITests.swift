import XCTest

/// ListenBrainz token flow + admin queue limit, driven end-to-end against the app's saved session on a server running
/// the 1.11 prerelease. Every assertion is a live server round-trip seen through the UI: toasts fire only on
/// POST /settings 200, and the queue field settling on the typed value is the GET-after-POST read-back.
/// setUp saves both settings through the app's DEBUG hook and tearDown puts them back and reads them again, also after
/// a failure. The server never returns a saved token, so when one is set the token part is left out entirely.
final class SettingsUITests: XCTestCase {
    private let app = XCUIApplication()
    /// The snapshot found a ListenBrainz token already saved.
    private var tokenWasSet = true
    /// The server-wide max queue length before the test.
    private var oldQueueLimit: Int?
    private var saved = false

    override func setUpWithError() throws {
        continueAfterFailure = true
        let line = serverState("snapshot", "queue-limit,scrobble-token")
        guard line.hasPrefix("saved:") else { throw XCTSkip("settings not saved first, so not changed: \(line)") }
        saved = true
        tokenWasSet = !line.contains("scrobble-token no token")
        oldQueueLimit = snapshotNumber(line, "queue-limit")
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        guard saved else { return }
        let line = serverState("restore", "queue-limit,scrobble-token")
        XCTAssertTrue(line.hasPrefix("restored:"), "settings not put back: \(line)")
    }

    /// Scroll until an element is hittable (`.exists` is true off-screen in
    /// lazy lists, and tap's auto-scroll then lands on the wrong row — the
    /// stats-page lesson), then tap it.
    @MainActor
    private func scrollToTap(_ el: XCUIElement, swipes: Int = 10) -> Bool {
        for _ in 0..<swipes where !el.isHittable {
            safeSwipeUp(app)
        }
        guard el.isHittable else { return false }
        el.tap()
        return true
    }

    /// Scroll-and-tap that re-queries every attempt. The scrobbling section swaps its view identity when GET /settings
    /// lands, so an XCUIElement captured earlier resolves against a dead tree ("No matches found for SecureTextField").
    /// Returns nil when the element never became hittable.
    @MainActor
    private func scrollToTapFresh(_ finder: @escaping () -> XCUIElement, swipes: Int = 12) -> XCUIElement? {
        // Scroll the Settings ScrollView, not the window: with the keyboard up, window-normalized swipe coordinates can
        // start inside the keyboard, and the ScrollView's frame (which excludes the keyboard) is where scrolls register.
        let scroller = app.scrollViews.firstMatch
        for _ in 0...swipes {
            let el = finder()
            if el.waitForExistence(timeout: 2), el.isHittable {
                el.tap()
                return el
            }
            safeSwipeUp(scroller)
        }
        return nil
    }

    /// More tab → settings.
    @MainActor
    private func openSettings() {
        let moreTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "more")).firstMatch
        XCTAssertTrue(moreTab.waitForExistence(timeout: 20), "shell never appeared")
        moreTab.tap()
        let settingsRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "settings")).firstMatch
        XCTAssertTrue(scrollToTap(settingsRow), "settings row not found in More")
    }

    @MainActor
    func testScrobblingAndQueueLimitAgainstLiveServer() throws {
        openSettings()
        if tokenWasSet {
            XCTContext.runActivity(named: "a ListenBrainz token is set and cannot be read back: not touched") { _ in }
        } else {
            scrobblingTokenRoundTrip()
            // A fresh launch, so a token-part failure leaves the queue part a clean start.
            app.terminate()
            app.launch()
            openSettings()
        }

        // --- Admin queue-limit row (web parity: hidden for non-admins). Changed by one, then put back by tearDown.
        guard let queueField = scrollToTapFresh({ self.app.textFields["queue-limit-field"] }, swipes: 12) else {
            throw XCTSkip("queue-limit row not present — session is not admin")
        }
        let old = queueField.value as? String ?? ""
        XCTAssertEqual(Int(old), oldQueueLimit, "queue limit not loaded from GET /system-settings")
        let base = Int(old) ?? 10000
        let target = base >= 100000 ? base - 1 : base + 1   // inside the server's 100...100000 range
        // Clear the old value then type: appending would send a number the server's range rejects.
        queueField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "\(target)")
        let queueSave = scrollToTapFresh({ self.app.buttons["queue-limit-save"] }, swipes: 4)
        XCTAssertNotNil(queueSave, "queue save never became hittable (keyboard?)")
        // The field settling on the target = the GET-after-POST read-back (the POST ack has no row fields). Fresh field
        // query each poll: the POST's settings reload can swap this section's identity mid-wait.
        func queueValue() -> String? { app.textFields["queue-limit-field"].value as? String }
        let deadline = Date().addingTimeInterval(15)
        var v = queueValue()
        while v != "\(target)" && Date() < deadline {
            _ = app.textFields["queue-limit-field"].waitForExistence(timeout: 1)
            v = queueValue()
        }
        XCTAssertEqual(v, "\(target)", "queue field did not settle on the saved server value")
        attachScreenshot("settings-queue-limit")
    }

    /// Saves a probe token, sees the server flag flip, removes it and sees the flag clear. Runs only when no token
    /// was set before, so removing it leaves the account as it was.
    @MainActor
    private func scrobblingTokenRoundTrip() {
        // --- §11 Scrobbling: save a token; the toast is the POST 200. -------
        // All interaction goes through scrollToTapFresh: the settings sections swap
        // view identity when their async loads land (ScrobblingSection.swift:36),
        // which kills elements captured earlier — the run-2 failure.
        guard let field1 = scrollToTapFresh({ self.app.secureTextFields["scrobbling-token"] }, swipes: 10) else {
            return XCTFail("scrobbling token field never rendered")
        }
        attachScreenshot("settings-scrobbling")
        // Return closes the keyboard. Wait for it to go: a tap while it slides away lands on the field, not on save.
        field1.typeText("lb-probe-token-99\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "keyboard stayed up after return")
        // The keyboard covers the save button; the helper scrolls it above the
        // keyboard (isHittable accounts for occlusion) instead of tapping blind.
        let save1 = scrollToTapFresh({ self.app.buttons["scrobbling-save"] }, swipes: 4)
        XCTAssertNotNil(save1, "save button never became hittable (stayed under the keyboard?)")
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "scrobbling on")).firstMatch
            .waitForExistence(timeout: 15)
        attachScreenshot("settings-scrobbling-saved")
        // The rest needs a saved token; stop here rather than cascade.
        guard saved else { return XCTFail("save toast never appeared (POST failed, or the typed token was lost)") }

        // Leaving and re-entering re-runs GET /settings; `configured` flips the section's shape. The "remove token" row
        // renders only when configured, so it proves the server's derived flag. (placeholderValue/label reads are dead
        // ends on iOS 26: SwiftUI SecureField exposes neither.) Fresh row query: the MoreView tree popped on navigation.
        app.navigationBars.firstMatch.buttons.firstMatch.tap()   // back to More
        let settingsRow2 = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "settings")).firstMatch
        XCTAssertTrue(scrollToTap(settingsRow2), "settings row gone on re-entry")
        XCTAssertTrue(app.secureTextFields["scrobbling-token"].waitForExistence(timeout: 10),
                      "field lost on re-entry")
        let removeToggle = app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", "remove token")).firstMatch
        XCTAssertTrue(removeToggle.waitForExistence(timeout: 10),
                      "server flag never flipped: no 'remove token' row after re-entry")

        // --- Clear it: toggle "remove token" → the save button relabels. ----
        let clearToggle = scrollToTapFresh(
            { self.app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", "remove token")).firstMatch },
            swipes: 6)
        XCTAssertNotNil(clearToggle, "remove-token toggle not found")
        let save2 = scrollToTapFresh({ self.app.buttons["scrobbling-save"] }, swipes: 0)   // label now "remove token"
        XCTAssertNotNil(save2, "save button vanished when the clear toggle appeared")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "token removed")).firstMatch
                      .waitForExistence(timeout: 15), "clear toast never appeared")
        // Flag back to false on re-entry: the "remove token" row only renders when
        // configured, so after a clear it must be GONE (the structural mirror of the
        // flip check above). Fresh row query — the MoreView tree popped on navigation.
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        let settingsRow3 = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "settings")).firstMatch
        XCTAssertTrue(scrollToTap(settingsRow3), "settings row gone after clear")
        XCTAssertTrue(app.secureTextFields["scrobbling-token"].waitForExistence(timeout: 10))
        let removedToggle = app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", "remove token")).firstMatch
        XCTAssertTrue(removedToggle.waitForNonExistence(timeout: 10),
                      "server flag never cleared: 'remove token' row still present after re-entry")
        attachScreenshot("settings-scrobbling-cleared")
    }
}
