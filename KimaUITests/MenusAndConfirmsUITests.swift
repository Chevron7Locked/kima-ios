import XCTest

/// The "•••" menus, the ask-first confirmations and the undo toast, seen against the simulator's saved session. Each
/// test opens one, keeps a screenshot, and closes it with cancel or a tap outside. Nothing is ever chosen: every menu
/// row and confirm button here changes the account's data. Skips (with a screenshot) when the account has nothing to
/// show the control on.
final class MenusAndConfirmsUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() { continueAfterFailure = false }

    override func tearDown() { app.terminate() }

    private func launch(_ args: [String]) {
        app.launchArguments = args
        app.launch()
    }

    /// Waits for `element`, keeps a screenshot either way, and fails when it never showed.
    @MainActor
    private func expectShown(_ element: XCUIElement, shot: String, _ what: String) {
        let shown = element.waitForExistence(timeout: 10)
        attachScreenshot(shown ? shot : "\(shot)-missing")
        XCTAssertTrue(shown, "\(what) never showed: \(app.debugDescription.prefix(4000))")
    }

    /// Closes a confirmation by its cancel button, or by a tap outside it when it shows none (iOS 26 shows these
    /// dialogs as popovers without one).
    @MainActor
    private func cancel(_ shown: XCUIElement, _ what: String) {
        let cancel = app.buttons["cancel"]
        if cancel.exists && cancel.isHittable {
            cancel.tap()
        } else {
            closeByTappingOutside()
        }
        XCTAssertTrue(shown.waitForNonExistence(timeout: 8), "\(what) stayed open after cancel")
    }

    /// A tap at the far left edge just under the status bar, where no menu or popover reaches and no control sits
    /// (the status bar itself does not take the tap): closes the menu or dialog without choosing a row.
    @MainActor
    private func closeByTappingOutside() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.09)).tap()
    }

    /// Scrolls until `element` is on screen (lazy pages report off-screen rows as existing).
    @MainActor
    private func scrollTo(_ element: XCUIElement, swipes: Int = 12) {
        for _ in 0..<swipes where !element.isHittable {
            safeSwipeUp(app)
            _ = element.waitForExistence(timeout: 2)
        }
    }

    @MainActor
    func testPlaylistMenuAndDeleteConfirm() throws {
        launch(["-kima-open", "playlist"])
        let menu = app.buttons["playlist-actions"]
        guard menu.waitForExistence(timeout: 30) else {
            attachScreenshot("playlist-no-detail")
            throw XCTSkip("no playlist opened (the account has no playlists)")
        }
        XCTAssertTrue(menu.isHittable, "playlist menu button not hittable")
        menu.tap()
        let hide = app.buttons.matching(NSPredicate(
            format: "label IN %@", ["hide from playlists", "show in playlists"])).firstMatch
        expectShown(hide, shot: "playlist-menu", "the playlist menu")

        let delete = app.buttons["delete playlist"]
        guard delete.exists else {
            closeByTappingOutside()
            XCTAssertTrue(hide.waitForNonExistence(timeout: 8), "the playlist menu stayed open")
            return   // someone else's playlist: no delete row
        }
        delete.tap()
        let title = app.staticTexts["delete playlist?"]
        expectShown(title, shot: "playlist-delete-confirm", "the delete confirmation")
        cancel(title, "the delete confirmation")
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "cancel left the playlist page")
    }

    @MainActor
    func testArtistDownloadAllAsksFirst() throws {
        launch(["-kima-open", "artist"])
        let menu = app.buttons["artist actions"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "artist actions menu missing")
        menu.tap()
        let download = app.buttons["download all"]
        guard download.waitForExistence(timeout: 5) else {
            attachScreenshot("artist-no-download-all")
            throw XCTSkip("the first artist has every album already, so the page offers no download all")
        }
        download.tap()
        let title = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH 'download ' AND label ENDSWITH '?'")).firstMatch
        expectShown(title, shot: "artist-download-all-confirm", "the download all confirmation")
        cancel(title, "the download all confirmation")
    }

    @MainActor
    func testAudiobookMenuOffersReset() throws {
        launch(["-kima-open", "audiobook-in-progress"])
        let more = app.buttons["more book actions"]
        guard more.waitForExistence(timeout: 30) else {
            attachScreenshot("audiobook-no-menu")
            throw XCTSkip("no book with saved progress, so no book page shows the menu")
        }
        scrollTo(more, swipes: 4)
        XCTAssertTrue(more.isHittable, "book menu button not hittable")
        attachScreenshot("audiobook-action-bar")
        more.tap()
        let reset = app.buttons["reset progress"]
        expectShown(reset, shot: "audiobook-menu", "the book menu")
        closeByTappingOutside()
        XCTAssertTrue(reset.waitForNonExistence(timeout: 8), "the book menu stayed open")
    }

    @MainActor
    func testPodcastEpisodeMenu() throws {
        launch(["-kima-open", "podcast"])
        let all = app.buttons.matching(NSPredicate(format: "label == %@", "episode actions"))
        guard all.firstMatch.waitForExistence(timeout: 30) else {
            attachScreenshot("podcast-no-episode-menu")
            throw XCTSkip("no subscribed podcast with an episode that has actions")
        }
        // The first row's menu sits below the fold, and scrolling passes it: take any menu in the middle of the
        // screen, clear of the header, the mini player and the tab bar.
        let band = app.frame.height * 0.2...app.frame.height * 0.7
        var actions: XCUIElement?
        for _ in 0..<4 {
            actions = all.allElementsBoundByIndex.first { $0.isHittable && band.contains($0.frame.midY) }
            if actions != nil { break }
            safeSwipeUp(app)
        }
        guard let actions else { return XCTFail("no episode menu button reachable on screen") }
        actions.tap()
        let row = app.buttons.matching(NSPredicate(
            format: "label IN %@", ["mark as played", "remove progress"])).firstMatch
        expectShown(row, shot: "podcast-episode-menu", "the episode menu")
        closeByTappingOutside()
        XCTAssertTrue(row.waitForNonExistence(timeout: 8), "the episode menu stayed open")
    }

    @MainActor
    func testDiscoverBuildAsksFirst() throws {
        launch(["-kima-open", "discover"])
        let build = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "build this week's playlist")).firstMatch
        guard build.waitForExistence(timeout: 30), build.isEnabled else {
            attachScreenshot("discover-no-build")
            throw XCTSkip("no build button (a build is running, or discover never loaded)")
        }
        scrollTo(build, swipes: 4)
        XCTAssertTrue(build.isHittable, "build button not hittable")
        build.tap()
        let title = app.staticTexts["build this week's playlist?"]
        expectShown(title, shot: "discover-build-confirm", "the build confirmation")
        cancel(title, "the build confirmation")
    }

    @MainActor
    func testMadeForYouRefreshAsksFirst() throws {
        launch([])
        let refresh = app.buttons["mixes-refresh"]
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "shell never appeared")
        scrollTo(refresh)
        XCTAssertTrue(refresh.isHittable, "refresh mixes not hittable")
        refresh.tap()
        let title = app.staticTexts["make new mixes?"]
        expectShown(title, shot: "mixes-refresh-confirm", "the make new mixes confirmation")
        cancel(title, "the make new mixes confirmation")
    }

    /// The undo toast as reset progress and hiding a playlist show it, raised by a DEBUG hook whose undo only
    /// toasts. Proves the toast's button shows and takes a tap; the real flows change data and are not run here.
    @MainActor
    func testUndoToastButtonWorks() throws {
        launch(["-kima-fake-undo-toast"])
        let undo = app.buttons["toast-action"]
        XCTAssertTrue(undo.waitForExistence(timeout: 30), "the undo toast never showed")
        attachScreenshot("undo-toast")
        XCTAssertEqual(undo.label, "undo")
        undo.tap()
        XCTAssertTrue(text(app, contains: "progress put back").waitForExistence(timeout: 5), "undo did nothing")
        attachScreenshot("undo-toast-after-tap")
    }
}
