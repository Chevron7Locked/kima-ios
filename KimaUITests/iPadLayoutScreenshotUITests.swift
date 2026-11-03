import XCTest

/// Screenshots of the iPad layout (sidebar shell) in both orientations, on the simulator's saved session. Navigation
/// only: launch hooks, sidebar rows, the now-playing bar and the player's queue button. Nothing it taps changes
/// server data. Skips on iPhone.
final class iPadLayoutScreenshotUITests: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    @MainActor
    func testLandscapeScreens() throws { try capture(.landscapeLeft, prefix: "land") }

    @MainActor
    func testPortraitScreens() throws { try capture(.portrait, prefix: "port") }

    /// The expanded sidebar (its playlists and settings rows), then the stats request the full player sends. Puts
    /// the sidebar back the way it was.
    @MainActor
    func testPortraitExpandedSidebar() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad only") }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-kima-tab", "0"]
        app.launch()
        sleep(8)
        fillScreen(app)
        add(XCTAttachment(string: app.debugDescription))
        let expand = app.buttons["expand sidebar"].firstMatch
        let wasCollapsed = expand.exists
        if wasCollapsed { expand.tap(); sleep(3) }
        attachScreenshot("portx-home")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        attachScreenshot("landx-home")
        XCUIDevice.shared.orientation = .portrait
        sleep(3)
        app.buttons["library"].firstMatch.tap(); sleep(6)
        attachScreenshot("portx-library")
        let settings = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "settings")).firstMatch
        if settings.waitForExistence(timeout: 5) {
            settings.tap(); sleep(5)
            attachScreenshot("portx-settings")
            safeSwipeUp(app); sleep(2)
            attachScreenshot("portx-settings-scrolled")
        }
        let playlist = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "01")).firstMatch
        if playlist.waitForExistence(timeout: 5) {
            playlist.tap(); sleep(8)
            attachScreenshot("portx-playlist")
        }
        if wasCollapsed { app.buttons["collapse sidebar"].firstMatch.tap(); sleep(2) }
        app.terminate()

        // The full player's stats link sends this request; on iPad there is no More tab to receive it.
        app.launchArguments = ["-kima-stats-request-after", "3"]
        app.launch()
        sleep(9)
        attachScreenshot("port-stats-request")
        app.terminate()
    }

    /// A narrow window (windowed apps: drag the window's bottom-right corner in): the layout falls back to the
    /// iPhone tab bar. The window is filled back to the whole screen afterwards.
    @MainActor
    func testNarrowWindow() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad only") }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-kima-tab", "0"]
        app.launch()
        sleep(8)
        fillScreen(app)
        let window = app.windows.firstMatch
        add(XCTAttachment(string: "window before: \(window.frame)"))
        // A window still wide enough for the sidebar: the window controls sit in its top-left corner.
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -6, dy: -6))
        corner.press(forDuration: 0.6, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 1)))
        sleep(4)
        attachScreenshot("windowed-sidebar")
        let wide = app.windows.firstMatch
        wide.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -6, dy: -6))
            .press(forDuration: 0.6, thenDragTo: wide.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 1)))
        sleep(4)
        add(XCTAttachment(string: "window narrow: \(app.windows.firstMatch.frame)"))
        attachScreenshot("narrow-home")
        let library = app.buttons["library"].firstMatch
        if library.waitForExistence(timeout: 3) { library.tap(); sleep(5); attachScreenshot("narrow-library") }
        fillScreen(app)
        attachScreenshot("narrow-restored")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        fillScreen(app)
        attachScreenshot("narrow-restored-portrait")
        app.terminate()
    }

    /// Fills the screen with the app window: windowed apps keep a resized window across launches, and shots
    /// of a part-screen window would not show the full-screen layout. Uses the system's fill shortcut,
    /// globe-control-F.
    @MainActor
    private func fillScreen(_ app: XCUIApplication) {
        app.typeKey("f", modifierFlags: [.function, .control])
        sleep(3)
    }

    /// Screens reached by a launch argument alone, with how long each takes to load.
    private let launched: [(name: String, args: [String], wait: UInt32)] = [
        ("home", ["-kima-tab", "0"], 8),
        ("album", ["-kima-open", "album"], 10),
        ("artist", ["-kima-open", "artist"], 10),
        ("audiobooks", ["-kima-tab", "2"], 8),
        ("audiobook", ["-kima-open", "audiobook"], 10),
        ("series", ["-kima-open", "series"], 10),
        ("podcasts", ["-kima-tab", "3"], 8),
        ("podcast", ["-kima-open", "podcast"], 10),
        ("browse-playlist", ["-kima-open", "browse-playlist"], 10),
        ("vibe", ["-kima-open", "vibe"], 12),
        ("activity", ["-kima-open", "activity"], 8),
        ("queue-route", ["-kima-open", "queue"], 12),
        ("sleep-timer", ["-kima-open", "sleep-timer"], 8),
        ("player-launch", ["-kima-open-player"], 8),
        // A kima://queue link while the full player is up opens the queue inside the player.
        ("player-queue-link", ["-kima-open-player", "-kima-open", "queue"], 12),
        ("playlist", ["-kima-open", "playlist"], 14),
        ("stats", ["-kima-open", "stats"], 12),
        // What the full player's play-count link sends; iPad opens the stats section.
        ("stats-request", ["-kima-stats-request-after", "3"], 12),
    ]

    @MainActor
    private func capture(_ orientation: UIDeviceOrientation, prefix: String) throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad only") }
        let app = XCUIApplication()

        for shot in launched {
            XCUIDevice.shared.orientation = orientation
            app.launchArguments = shot.args
            app.launch()
            XCUIDevice.shared.orientation = orientation
            if shot.name == launched.first?.name { sleep(4); fillScreen(app) }
            sleep(shot.wait)
            attachScreenshot("\(prefix)-\(shot.name)")
            app.terminate()
        }

        // Library tabs, then the sidebar destinations, in one launch.
        XCUIDevice.shared.orientation = orientation
        app.launchArguments = ["-kima-tab", "1"]
        app.launch()
        XCUIDevice.shared.orientation = orientation
        sleep(8)
        attachScreenshot("\(prefix)-library-artists")
        for tab in ["albums", "tracks"] {
            let b = app.buttons[tab].firstMatch
            if b.waitForExistence(timeout: 5) { b.tap(); sleep(5); attachScreenshot("\(prefix)-library-\(tab)") }
        }
        for item in ["playlists", "discover", "radio", "stats", "search", "settings"] {
            let row = app.buttons.matching(NSPredicate(format: "label ==[c] %@ OR label ENDSWITH[c] %@", item, ", \(item)")).firstMatch
            guard row.waitForExistence(timeout: 5) else { attachScreenshot("\(prefix)-missing-\(item)"); continue }
            row.tap()
            sleep(["discover", "stats", "playlists"].contains(item) ? 8 : 5)
            attachScreenshot("\(prefix)-\(item)")
        }
        // Search with a query (results are reads only).
        let home = app.buttons["home"].firstMatch
        let search = app.buttons["search"].firstMatch
        if search.exists {
            search.tap(); sleep(2)
            let field = app.textFields.firstMatch
            if field.waitForExistence(timeout: 5) {
                field.tap(); field.typeText("love"); sleep(6)
                attachScreenshot("\(prefix)-search-query")
            }
        }
        // First playlist in the sidebar's playlist list.
        let playlist = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "01")).firstMatch
        if playlist.waitForExistence(timeout: 5), playlist.isHittable {
            playlist.tap(); sleep(8)
            attachScreenshot("\(prefix)-playlist")
        }
        // Collapsed sidebar on home, then expanded again (a device-local setting).
        if home.exists { home.tap(); sleep(3) }
        let collapse = app.buttons["collapse sidebar"].firstMatch
        if collapse.exists {
            collapse.tap(); sleep(3)
            attachScreenshot("\(prefix)-home-sidebar-collapsed")
            app.buttons["expand sidebar"].firstMatch.tap(); sleep(2)
        }
        // Full player from the now-playing bar, then its queue.
        let bar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "now playing:")).firstMatch
        if bar.waitForExistence(timeout: 10) {
            attachScreenshot("\(prefix)-now-playing-bar")
            bar.tap(); sleep(4)
            attachScreenshot("\(prefix)-player")
            let queue = app.buttons["queue"].firstMatch
            if queue.waitForExistence(timeout: 5) { queue.tap(); sleep(4); attachScreenshot("\(prefix)-player-queue") }
        } else {
            attachScreenshot("\(prefix)-no-now-playing-bar")
        }
        app.terminate()
    }
}
