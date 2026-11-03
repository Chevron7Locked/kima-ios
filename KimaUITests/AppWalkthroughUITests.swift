import XCTest

/// A tap-through of the whole app against the signed-in session: every tab, the pages each leads to, the player, the
/// queue, long-press menus, search and settings. Read-only: nothing that changes the account is ever confirmed, and
/// playback runs for at most a few seconds (a play is counted only after half the song). Every step keeps a
/// screenshot; a step that cannot find its control records a "-missing" shot and the walk goes on.
final class AppWalkthroughUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() { continueAfterFailure = true }

    override func tearDown() { app.terminate() }

    // MARK: - Helpers

    /// Set when something started playback the walk did not ask for; every later step is skipped.
    private var stopped = false

    private func shot(_ name: String) {
        attachScreenshot(name)
        XCTAssertEqual(app.state, .runningForeground, "the app is not running after \(name)")
        guardNotPlaying(after: name)
    }

    /// Playback the walk did not start ends the walk: pauses at once, records the step, and stops.
    private func guardNotPlaying(after step: String) {
        guard !stopped, !playbackAllowed else { return }
        let pause = app.buttons["pause"].firstMatch
        guard pause.exists else { return }
        if pause.isHittable { pause.tap() }
        stopped = true
        attachScreenshot("\(step)-started-playback")
        XCTFail("playback started during or before \(step); paused and stopped the walk")
    }

    /// True only during the player step's own few seconds of playback.
    private var playbackAllowed = false

    /// The part of the screen a tap may land in: under the header, above the mini player and tab bar.
    private var safeBand: ClosedRange<CGFloat> { 110...(app.frame.height * 0.76) }

    private func inSafeBand(_ e: XCUIElement) -> Bool {
        e.exists && e.isHittable && safeBand.contains(e.frame.midY) && e.frame.maxY < safeBand.upperBound + 20
    }

    /// A short drag that moves the page about a fifth of the screen.
    private func nudge(up: Bool) {
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.6 : 0.4))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.4 : 0.6))
        a.press(forDuration: 0.05, thenDragTo: b)
    }

    private func label(_ needle: String) -> NSPredicate {
        NSPredicate(format: "label ==[c] %@", needle)
    }

    /// The first element whose label is `needle`, buttons first.
    private func element(_ needle: String) -> XCUIElement {
        let button = app.buttons.matching(label(needle)).firstMatch
        if button.exists { return button }
        return app.descendants(matching: .any).matching(label(needle)).firstMatch
    }

    /// Scrolls up to `swipes` times until `needle` can be tapped, then taps it. Records a "-missing" shot when it
    /// never shows.
    /// Only taps inside `safeBand`, so a control scrolled under the mini player is never tapped through it.
    @discardableResult
    private func tap(_ needle: String, swipes: Int = 6, wait: TimeInterval = 8, step: String) -> Bool {
        guard !stopped else { return false }
        var target = element(needle)
        _ = target.waitForExistence(timeout: wait)
        for _ in 0..<(swipes * 4) where !inSafeBand(target) {
            if target.exists, target.frame.midY < safeBand.lowerBound { nudge(up: false) }
            else if target.exists, target.frame.midY < app.frame.height * 1.5 { nudge(up: true) }
            else { app.swipeUp() }
            target = element(needle)
        }
        guard inSafeBand(target) else {
            shot("\(step)-missing")
            XCTFail("\(step): no \"\(needle)\" to tap")
            return false
        }
        target.tap()
        guardNotPlaying(after: step)
        return true
    }

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no \(name) tab")
        button.tap()
        // Back to the tab's root when it was left on a pushed page.
        button.tap()
        sleep(2)
    }

    /// Scrolls the page down in steps, keeping a shot every other swipe, then back to the top.
    private func scrollPage(_ name: String, swipes: Int = 6) {
        guard !stopped else { return }
        shot("\(name)-top")
        for i in 1...swipes {
            app.swipeUp()
            if i % 2 == 0 { shot("\(name)-scroll-\(i)") }
        }
        for _ in 0..<swipes { app.swipeDown(velocity: .fast) }
    }

    /// Back one page: the navigation back button when there is one, else an edge swipe.
    private func back() {
        let navBack = app.navigationBars.buttons.element(boundBy: 0)
        if navBack.exists, navBack.isHittable {
            navBack.tap()
        } else {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        }
        sleep(1)
    }

    /// Closes a sheet by dragging it down from its top.
    private func closeSheet() {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        top.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        sleep(1)
    }

    /// The first grid card or row whose spoken label has "title, subtitle" shape, in the page body: below the
    /// header and above the mini player and tab bar.
    private func firstItem() -> XCUIElement {
        let floor = app.frame.height * 0.72
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS ', ' AND NOT (label BEGINSWITH 'kima') AND identifier != 'expand-player'"))
            .allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > 150 && $0.frame.maxY < floor && !$0.label.hasPrefix("pause") && !$0.label.hasPrefix("play") }
            ?? app.otherElements["none"]
    }

    /// Opens the first item on the page, shoots and scrolls it, and comes back.
    private func openFirst(_ name: String, swipes: Int = 4) {
        guard !stopped else { return }
        let item = firstItem()
        guard item.waitForExistence(timeout: 10), item.isHittable else {
            shot("\(name)-missing"); XCTFail("\(name): nothing to open"); return
        }
        item.tap()
        sleep(3)
        guardNotPlaying(after: name)
        scrollPage(name, swipes: swipes)
        back()
    }

    /// Long-presses the first item, checks the menu offers no delete, and closes it without choosing.
    private func checkMenu(_ name: String) {
        guard !stopped else { return }
        let item = firstItem()
        guard item.waitForExistence(timeout: 10) else { shot("\(name)-missing"); XCTFail("\(name): no item"); return }
        item.press(forDuration: 1.2)
        let play = app.buttons["play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5), "\(name): no menu")
        XCTAssertFalse(app.buttons["delete"].exists, "\(name): the menu offers delete")
        shot(name)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.09)).tap()
        _ = play.waitForNonExistence(timeout: 5)
    }

    // MARK: - The walk

    func testWalkTheWholeApp() throws {
        app.launchArguments = ["-kima-no-whatsnew", "-kima-log-dump"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["home"].waitForExistence(timeout: 30), "the app never reached its tabs")
        sleep(6)

        XCTContext.runActivity(named: "home") { _ in
            tab("home")
            scrollPage("home", swipes: 8)
            if tap("see all", swipes: 2, step: "home-see-all") { sleep(3); scrollPage("home-see-all", swipes: 2); back() }
            let bell = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'notification' OR label CONTAINS[c] 'activity'")).firstMatch
            if bell.waitForExistence(timeout: 3) {
                bell.tap(); sleep(2); shot("activity"); closeSheet()
            } else { shot("activity-missing") }
        }

        XCTContext.runActivity(named: "library") { _ in
            tab("library")
            for section in ["artists", "albums", "tracks"] {
                if tap(section, swipes: 0, step: "library-\(section)") {
                    sleep(3)
                    scrollPage("library-\(section)", swipes: 4)
                    checkMenu("library-\(section)-menu")
                    if section != "tracks" { openFirst("library-\(section)-open") }
                }
            }
        }

        XCTContext.runActivity(named: "player and queue") { _ in
            let expand = app.descendants(matching: .any)["expand-player"]
            guard expand.waitForExistence(timeout: 5) else { shot("player-missing"); return }
            expand.tap(); sleep(2); shot("player")
            // The one deliberate playback: five seconds, far short of the half-song that counts as a play.
            let play = app.buttons["play"].firstMatch
            if play.waitForExistence(timeout: 3), play.isHittable {
                playbackAllowed = true
                play.tap(); sleep(5); attachScreenshot("player-playing")
                app.buttons["pause"].firstMatch.tap(); sleep(1)
                playbackAllowed = false
                shot("player-paused")
            } else { shot("player-play-missing") }
            let queue = app.descendants(matching: .any)["queue-button"]
            if queue.waitForExistence(timeout: 3) {
                queue.tap(); sleep(2); shot("queue")
                app.swipeUp(); shot("queue-scrolled")
                if app.buttons["edit"].exists {
                    app.buttons["edit"].tap(); sleep(1); shot("queue-editing")
                    app.buttons["done"].tap()
                }
                closeSheet()
            } else { shot("queue-missing") }
            closeSheet()
            shot("player-closed")
        }

        XCTContext.runActivity(named: "audiobooks") { _ in
            tab("audiobooks")
            scrollPage("audiobooks", swipes: 6)
            openFirst("audiobook-open")
        }

        XCTContext.runActivity(named: "podcasts") { _ in
            tab("podcasts")
            scrollPage("podcasts", swipes: 8)
            openFirst("podcast-open", swipes: 6)
            if tap("see all", swipes: 8, step: "podcast-see-all") { sleep(4); scrollPage("podcast-chart", swipes: 4); back() }
        }

        XCTContext.runActivity(named: "more") { _ in
            let pages = ["discover weekly", "library radio", "new releases", "browse playlists", "playlists", "stats",
                         "downloads", "import", "settings"]
            for page in pages {
                tab("more")
                let name = "more-" + page.replacingOccurrences(of: " ", with: "-")
                guard tap(page, step: name) else { continue }
                sleep(4)
                scrollPage(name, swipes: page == "stats" || page == "settings" ? 10 : 4)
                if page == "playlists" || page == "browse playlists" { openFirst("\(name)-open") }
                if page == "settings", tap("changelog", swipes: 10, step: "changelog") {
                    sleep(3); scrollPage("changelog", swipes: 3); back()
                }
                back()
            }

            tab("more")
            if tap("vibe map", step: "vibe") {
                sleep(8); shot("vibe-map")
                let close = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'close' OR label CONTAINS[c] 'back'")).firstMatch
                if close.exists { close.tap() } else { back() }
                sleep(2)
            }

            tab("more")
            if tap("report a problem", step: "report") { sleep(2); shot("report"); closeSheet() }

            tab("more")
            let search = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch
            if search.waitForExistence(timeout: 5) {
                search.tap(); search.typeText("the"); sleep(4); shot("search-results")
                app.swipeUp(); shot("search-results-scrolled")
                let cancel = app.buttons["cancel"]
                if cancel.exists { cancel.tap() }
            } else { shot("search-missing") }
        }

        tab("home")
        shot("end")
    }
}
