import XCTest

/// The what's-new release-window gate. Three tests: (1) synthetic UI path (`-kima-whatsnew 2`): a two-release queue
/// proves oldest-first order, one window at a time, the note and list on the overview, an item's own page and the way
/// back, Done closing each, and landing back on the shell; (2) live server path: uses the simulator's saved session and
/// POSTs dismissals, which mark those releases seen for good, so it runs only against a seeded test account
/// (`TEST_RUNNER_KIMA_UITEST_SEEDED_ACCOUNT=1`) and skips otherwise; (3) a read-only live look at the 1.11 note and
/// the ListenBrainz copy, which taps nothing that records an answer.
final class WhatsNewUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Same for buttons (CTAs and answer buttons are Buttons, not staticTexts).
    private func button(_ app: XCUIApplication, contains needle: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", needle, needle)).firstMatch
    }

    @MainActor
    func testSyntheticWindowQueueShowsOldestFirstAndCloses() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-kima-whatsnew", "2"]
        app.launch()

        let done = app.buttons["whatsnew-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 30), "release window never appeared")

        // Oldest first: window A (9.99.1), not B.
        XCTAssertTrue(text(app, contains: "probe release a").waitForExistence(timeout: 8),
                      "first window is not the older release")
        XCTAssertFalse(text(app, contains: "probe release b").exists,
                       "the queue must show one window at a time")

        // The window opens on the note, with the items listed beside/below it.
        XCTAssertTrue(text(app, contains: "a note from kevin").waitForExistence(timeout: 8),
                      "the window did not open on the maintainer's note")
        XCTAssertTrue(text(app, contains: "hey y'all").waitForExistence(timeout: 5),
                      "the note's body did not render")
        XCTAssertTrue(text(app, contains: "what's new in 9.99").waitForExistence(timeout: 5),
                      "the list heading did not render")
        XCTAssertTrue(text(app, contains: "needs you").waitForExistence(timeout: 5),
                      "the choice did not group under needs you")
        XCTAssertTrue(text(app, contains: "what changed").waitForExistence(timeout: 5),
                      "the note item did not group under what changed")

        // The list shows the one-liner, and the answers live on the item's own page.
        XCTAssertTrue(text(app, contains: "dismissing records the default").waitForExistence(timeout: 5),
                      "the list line is missing the item's summary")
        XCTAssertFalse(button(app, contains: "turn it on").exists,
                       "answer buttons belong on the item's page, not in the list")

        app.buttons["whatsnew-row-probe.choice"].tap()
        XCTAssertTrue(app.buttons["turn it on"].waitForExistence(timeout: 5),
                      "the item's page did not show its answers")
        XCTAssertTrue(text(app, contains: "kevin's note").waitForExistence(timeout: 5),
                      "the page's back link does not name the note")
        XCTAssertTrue(text(app, contains: "if you don't answer, it stays off").waitForExistence(timeout: 5),
                      "the page did not say what not answering means")

        // Back returns to the note and the list; nothing was answered, so the footer still waits.
        app.buttons["whatsnew-back"].tap()
        XCTAssertTrue(text(app, contains: "a note from kevin").waitForExistence(timeout: 5),
                      "back did not return to the note")
        XCTAssertTrue(app.buttons["whatsnew-waiting"].waitForExistence(timeout: 5),
                      "the footer did not name what is waiting")

        done.tap()
        XCTAssertTrue(text(app, contains: "probe release b").waitForExistence(timeout: 8),
                      "second window never followed")
        attachScreenshot("whatsnew-synthetic-B")
        done.tap()

        XCTAssertFalse(done.waitForExistence(timeout: 3), "window still up after closing both")
    }

    /// The run-from-window action, the shape the server sends as `run:"wipeEnrichment"`. iOS once looked for a
    /// `runsFromWindow` flag the server has never emitted, which hid this whole action; this proves it renders, asks,
    /// and says what closing means. The confirm is cancelled — running it would wipe a live library's enrichment.
    @MainActor
    func testRunFromWindowActionAsksBeforeItRuns() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-kima-whatsnew", "5"]
        app.launch()

        XCTAssertTrue(app.buttons["whatsnew-row-engine.wipe"].waitForExistence(timeout: 30),
                      "the wipe action is not in the list")
        XCTAssertTrue(text(app, contains: "needs you").waitForExistence(timeout: 5),
                      "a decision action must group under needs you")

        app.buttons["whatsnew-row-engine.wipe"].tap()
        let run = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "wipe and re-run")).firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 5), "the run action's button did not render")
        XCTAssertTrue(text(app, contains: "if you close now, nothing is wiped").waitForExistence(timeout: 5),
                      "the page did not say what closing without acting means")

        // The map link is the 1.11 copy's `/vibe` target — follow it and prove it opens the map.
        let mapLink = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "open the vibe map")).firstMatch
        XCTAssertTrue(mapLink.waitForExistence(timeout: 5), "the item's map link did not render")
        mapLink.tap()

        XCTAssertTrue(app.buttons["whatsnew-done"].waitForNonExistence(timeout: 10),
                      "the window stayed up after following its link")
        XCTAssertTrue(app.staticTexts["vibe-track-count"].waitForExistence(timeout: 30),
                      "the /vibe link did not open the vibe map")
    }

    /// Read-only against the simulator's live session: the 1.11 window's note and the ListenBrainz
    /// "recommended, never required" paragraph, as the server wrote them. Nothing here taps an answer or
    /// Done, so no release is marked seen and nothing is run.
    @MainActor
    func testLiveNoteCarriesTheListenBrainzCopy() throws {
        let app = XCUIApplication()
        app.launch()   // simulator's saved session; no args

        guard app.buttons["whatsnew-note"].waitForExistence(timeout: 30) else {
            attachScreenshot("whatsnew-live-no-note")
            throw XCTSkip("no live window with a note — the account has nothing pending, "
                          + "or its releases were already closed")
        }
        XCTAssertTrue(text(app, contains: "a note from").waitForExistence(timeout: 5),
                      "the note heading did not render")

        let lbRow = app.buttons["whatsnew-row-lastfm.gone"]
        guard lbRow.waitForExistence(timeout: 5) else {
            attachScreenshot("whatsnew-live-no-lastfm-row")
            throw XCTSkip("this server's pending release has no no-accounts item")
        }
        lbRow.tap()
        XCTAssertTrue(text(app, contains: "listenbrainz is recommended for popularity, never required")
                        .waitForExistence(timeout: 8),
                      "the ListenBrainz recommended-not-required copy did not reach the app verbatim")
        XCTAssertTrue(text(app, contains: "deezer keeps filling it in").waitForExistence(timeout: 5),
                      "the Deezer fallback sentence did not render")
        attachScreenshot("whatsnew-live-listenbrainz-copy")
    }

    @MainActor
    func testLiveGateWalksServerPendingQueue() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KIMA_UITEST_SEEDED_ACCOUNT"] == "1",
                          "closing a live window marks that release seen for the account; seeded test accounts only")
        let app = XCUIApplication()
        app.launch()   // simulator's saved session (seeded testbed); no args

        let done = app.buttons["whatsnew-done"]
        guard done.waitForExistence(timeout: 30) else {
            attachScreenshot("whatsnew-live-no-gate")
            throw XCTSkip("gate never opened — simulator session missing/sign-out, "
                          + "or the server has no pending releases for this user")
        }
        // the seeded test account's queue: 1.10.1 → 1.12.0 → synthesized re-ask.
        XCTAssertTrue(text(app, contains: "what counts as a play").waitForExistence(timeout: 10))
        app.buttons["whatsnew-row-plays.repair"].tap()
        XCTAssertTrue(button(app, contains: "open the cleanup").waitForExistence(timeout: 5),
                      "plays.repair's link did not render on its page")
        attachScreenshot("whatsnew-live-1101")
        app.buttons["whatsnew-back"].tap()
        done.tap()

        XCTAssertTrue(text(app, contains: "the engine rebuild").waitForExistence(timeout: 10),
                      "1.12.0 window never followed 1.10.1")
        attachScreenshot("whatsnew-live-1120")
        done.tap()

        // The seeded retired mood-mix (no decision, no playlist) must come
        // back on its own — server-synthesized "One thing left from 1.11".
        XCTAssertTrue(text(app, contains: "one thing left from 1.11").waitForExistence(timeout: 10),
                      "mood-mix re-ask window never appeared")
        // The panel lives on the item's page; its state loads async
        // (GET /whats-new/mood-mixes in the panel's .task) — hence the waits.
        app.buttons["whatsnew-row-moods.mixes.retired"].tap()
        XCTAssertTrue(text(app, contains: "High Energy Mix").waitForExistence(timeout: 10),
                      "retired mix name did not render")
        XCTAssertTrue(app.buttons["moodmix-save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["moodmix-remove"].exists)
        XCTAssertFalse(app.buttons["moodmix-rebuild"].exists,
                       "retired mix must not offer rebuild/keep")
        attachScreenshot("whatsnew-live-moodmix")
        done.tap()
    }
}
