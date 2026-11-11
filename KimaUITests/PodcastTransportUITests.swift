import XCTest

/// SMOKE — the end-to-end proof of the transport display contract (ADR 0001); run it whenever
/// transport display derivation changes. The glyph matrix itself is unit-tested at the controller
/// seam (`PlaybackAudibleTests`); this suite proves the real views render it in agreement.
/// Podcast transport sync (the build-20 bug report): with a podcast session paused, nothing on the detail page
/// may claim it is playing; with it playing, everything must say so. The mini player's transport disc mirrors
/// engine state; the hero and episode rows derive their display from the session — this bug lives in that
/// derivation. `-kima-fake-podcast` seeds the page and a true engine state with no server (`DebugPodcastSeed`).
final class PodcastTransportUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() { continueAfterFailure = false }

    override func tearDown() { app.terminate() }

    /// Launch onto the seeded "seed station" detail page with a podcast session whose engine is in `mode`.
    private func launch(seeded mode: String) {
        app.launchArguments = ["-kima-fake-signed-in", "-kima-no-whatsnew",
                               "-kima-open", "podcast", "-kima-fake-podcast", mode]
        app.launch()
        XCTAssertTrue(app.staticTexts["continue listening"].waitForExistence(timeout: 30),
                      "the seeded detail page did not appear")
    }

    /// Launch and prove the seed first: the transport disc mirrors engine state, so its label is
    /// the oracle for "the engine really started in `mode`" — every test reads it before asking
    /// anything derived.
    private func launchValidated(seeded mode: String, transportShows expected: String) {
        launch(seeded: mode)
        XCTAssertTrue(transport.waitForExistence(timeout: 10), "the mini player did not show the seeded session")
        XCTAssertEqual(transport.label, expected, "seed validity: \(mode) engine state did not reach the transport")
    }

    /// The mini player's transport disc — the control that mirrors engine state.
    private var transport: XCUIElement { app.buttons["now-playing-play"].firstMatch }

    /// The detail page's one amber hero control.
    private var hero: XCUIElement { app.buttons["hero-play"] }

    /// Every play/pause control for "seed one": the continue-stack copy and the episode-list row (this page
    /// shows the same episode twice).
    private func seed1Rows() -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier == 'episode-play' AND label CONTAINS[c] 'seed one'"))
    }

    /// Engine paused: the transport proves the seed, and no page control may read as playing.
    func testPausedSessionNeverReadsAsPlaying() throws {
        launchValidated(seeded: "paused", transportShows: "play")

        // Probed before any scroll: a swipe-up gesture collapses the mini player. "resume" pins both halves:
        // not playing (display truth) and this show owning the session (so the fix can't pass by losing it).
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        XCTAssertEqual(hero.label, "resume", "the hero of a paused owned session should read resume")

        app.swipeUp()   // the episode list's copy of seed one lives below the fold (LazyVStack unmounts it)
        let rows = seed1Rows()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "the seeded episode's row did not appear")
        for n in 0 ..< rows.count {
            let label = rows.element(boundBy: n).label.lowercased()
            XCTAssertFalse(label.hasPrefix("pause"), "an episode row shows pause while the engine is paused: \(label)")
        }
    }

    /// The published lock-screen / Control Center state, read back from the system's now-playing
    /// center by the DEBUG probe (ticket 03). This is what the lock screen offers to a tap.
    private var lockScreen: XCUIElement { app.staticTexts["lock-screen-published"] }

    /// The publish lands on launch; wait for the reading rather than race it (marker precedent:
    /// VibeReplaceUITests.expectOrigin).
    private func expectPublished(_ name: String) {
        XCTAssertTrue(lockScreen.waitForExistence(timeout: 10), "the lock-screen probe never mounted")
        expectation(for: NSPredicate(format: "label == %@", name), evaluatedWith: lockScreen)
        waitForExpectations(timeout: 10)
    }

    // MARK: - Lock screen (ticket 03): the published state is the derived one, not engine identity

    /// The bug's last surface: during a fetch window the lock screen offered play while a tap
    /// paused. It must offer pause — published playing — while the app itself holds waiting.
    func testFetchWindowLockScreenShowsPause() throws {
        launchValidated(seeded: "waiting", transportShows: "pause")   // the app holds waiting
        expectPublished("playing")   // lock screen shows pause; a tap stops the fetch
    }

    /// A paused session publishes paused: the lock screen offers play, and a tap resumes.
    func testPausedSessionLockScreenShowsPlay() throws {
        launchValidated(seeded: "paused", transportShows: "play")
        expectPublished("paused")
    }

    /// A resting session publishes stopped — the two-valued publish could only ever say paused.
    func testStoppedSessionLockScreenSaysStopped() throws {
        launchValidated(seeded: "stopped", transportShows: "play")   // held session, engine at rest
        expectPublished("stopped")
    }

    /// Engine playing: every control says so — the same agreement, read the other way. Green before the fix
    /// (identity derivation coincides with truth here); red if a fix keys page state off anything else.
    func testPlayingSessionReadsAsPlayingEverywhere() throws {
        launchValidated(seeded: "playing", transportShows: "pause")

        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        XCTAssertEqual(hero.label, "pause", "the hero does not show pause while the engine is playing")

        expectPublished("playing")   // and the lock screen agrees

        app.swipeUp()
        let rows = seed1Rows()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "the seeded episode's row did not appear")
        for n in 0 ..< rows.count {
            let label = rows.element(boundBy: n).label.lowercased()
            XCTAssertTrue(label.hasPrefix("pause"), "an episode row does not show pause while playing: \(label)")
        }
    }
}
