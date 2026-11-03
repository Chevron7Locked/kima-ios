import XCTest

/// Map controls on the synthetic 9,000-track map (no server, no playback):
/// mood legend, pinning, long-press, the song path flow, blend from a star, the rail, top-bar buttons.
final class VibeMapUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-kima-fake-signed-in", "-kima-vibe-synthetic", "-kima-open", "vibe",
                              "-kima.vibe.helpSeen", "NO"]
        app.launch()
    }

    override func tearDown() { app.terminate() }

    private var chips: XCUIElementQuery { app.buttons.matching(identifier: "vibe-legend-chip") }

    private func waitForMap() {
        XCTAssertTrue(app.staticTexts["vibe-track-count"].waitForExistence(timeout: 30), "map never loaded")
    }

    @MainActor
    func testLegendIsLowercaseCountsAddUpAndMoodsComeFirst() throws {
        waitForMap()
        XCTAssertEqual(app.staticTexts["vibe-track-count"].label, "9,000 tracks")
        XCTAssertGreaterThanOrEqual(chips.count, 5)
        var total = 0
        var labels: [String] = []
        for i in 0..<chips.count {
            let chip = chips.element(boundBy: i)
            let parts = chip.label.components(separatedBy: ", ")
            labels.append(parts[0])
            XCTAssertEqual(chip.label, chip.label.lowercased())
            total += Int((parts.last ?? "").replacingOccurrences(of: ",", with: "")) ?? 0
        }
        XCTAssertEqual(total, 9000, "chip counts \(labels)")
        let moods: Set = ["upbeat", "melancholic", "calm", "intense", "energetic"]
        XCTAssertTrue(Set(labels.prefix(5)).isSubset(of: moods), "five moods should come first: \(labels)")
        if labels.count > 5 { XCTAssertEqual(labels[5], "no single mood") }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "vibe-legend"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor
    func testBackClosesHelpFirstThenUnpins() throws {
        waitForMap()
        let back = app.buttons["vibe-clear"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the first visit's help list is something to close")
        XCTAssertEqual(back.label, "close help")
        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 5), "nothing left to undo: back hides")
        let first = chips.element(boundBy: 0)
        first.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5), "back should appear while a mood is pinned")
        XCTAssertTrue(back.label.hasPrefix("unpin "), back.label)
        XCTAssertTrue(first.isSelected)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "vibe-pinned"; shot.lifetime = .keepAlways; add(shot)
        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 5))
        XCTAssertFalse(chips.element(boundBy: 0).isSelected)
    }

    @MainActor
    func testLongPressSelectsAndTheReadoutAddsToBlend() throws {
        waitForMap()
        let star = app.otherElements["vibe-debug-star"]
        XCTAssertTrue(star.waitForExistence(timeout: 20), "no on-screen star to press")
        star.press(forDuration: 0.8)
        XCTAssertTrue(app.staticTexts["vibe-tray-title"].waitForExistence(timeout: 5), "long-press selects the star")
        XCTAssertFalse(app.buttons["song path from here"].exists, "no system menu")
        XCTAssertFalse(app.sheets.firstMatch.exists, "no system menu")
        app.buttons["vibe-tray-more"].tap()
        XCTAssertTrue(app.textFields["vibe-blend-search"].waitForExistence(timeout: 5), "more like opens blend")
        XCTAssertEqual(app.buttons["vibe-blend-more"].label, "more like, 1 track", "the star is in more like")
        XCTAssertTrue(app.buttons["vibe-blend-go"].isEnabled)

        // Back closes the panel and keeps the pick; the readout comes back for the still-selected star.
        XCTAssertEqual(app.buttons["vibe-clear"].label, "close blend")
        app.buttons["vibe-clear"].tap()
        XCTAssertTrue(app.staticTexts["vibe-tray-title"].waitForExistence(timeout: 5))
        app.buttons["vibe-tray-less"].tap()
        XCTAssertTrue(app.textFields["vibe-blend-search"].waitForExistence(timeout: 5), "less like opens blend")
        XCTAssertEqual(app.buttons["vibe-blend-more"].label, "more like, 1 track", "more like kept")
        XCTAssertEqual(app.buttons["vibe-blend-less"].label, "less like, 1 track", "less like added")
        // A side's line lists its tracks, each with a × that removes it.
        app.buttons["vibe-blend-less"].tap()
        let remove = app.buttons["vibe-blend-remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(app.descendants(matching: .any)["vibe-blend-less"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["vibe-blend-less"].label, "less like, 0 tracks")
    }

    @MainActor
    func testRailSongPathStartsFromTheSelectedStar() throws {
        waitForMap()
        let star = app.otherElements["vibe-debug-star"]
        XCTAssertTrue(star.waitForExistence(timeout: 20), "no on-screen star to tap")
        star.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["vibe-tray-title"].waitForExistence(timeout: 5))
        app.buttons["vibe-rail-songpath"].tap()
        // The start is the selected star; the one prompt left asks for the end.
        XCTAssertTrue(app.descendants(matching: .any)["vibe-path-start-pick"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["vibe-path-end"].exists)
        XCTAssertFalse(app.textFields["vibe-path-start"].exists, "one prompt at a time")
        // Back undoes the newest thing: the panel closes, the start stays for next time.
        app.buttons["vibe-clear"].tap()
        XCTAssertTrue(app.textFields["vibe-path-end"].waitForNonExistence(timeout: 5))
        app.buttons["vibe-rail-songpath"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["vibe-path-start-pick"].waitForExistence(timeout: 5),
                      "reopening keeps the start")
    }

    @MainActor
    func testTappingAStarShowsTheSongCard() throws {
        // Zoomed all the way out, so the screen's edges are empty space to tap.
        app.terminate()
        app.launchArguments += ["-kima-vibe-zoom-out"]
        app.launch()
        waitForMap()
        let star = app.otherElements["vibe-debug-star"]
        XCTAssertTrue(star.waitForExistence(timeout: 20), "no on-screen star to tap")
        let title = app.staticTexts["vibe-tray-title"]
        XCTAssertFalse(title.exists, "tray should start without a track")
        XCTAssertTrue(app.descendants(matching: .any)["vibe-tray-help"].waitForExistence(timeout: 5), "first visit shows the help line")
        star.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(title.waitForExistence(timeout: 5), "tapping a star should show the tray")
        XCTAssertFalse(title.label.isEmpty, "tray has no title")
        XCTAssertTrue(app.buttons["vibe-tray-artist"].exists, "tray is missing the artist")
        for id in ["vibe-tray-play", "vibe-tray-play-similar", "vibe-tray-similar", "vibe-tray-more", "vibe-tray-less",
                   "vibe-tray-album"] {
            XCTAssertTrue(app.buttons[id].exists, "tray is missing \(id)")
        }
        XCTAssertTrue(app.descendants(matching: .any)["vibe-tray-cover"].exists, "readout is missing the cover")
        XCTAssertFalse(app.buttons["vibe-tray-cover"].exists, "the album link is the one way to the album")
        XCTAssertFalse(app.descendants(matching: .any)["vibe-tray-help"].exists, "tapping a star closes the help list")
        let card = title
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "vibe-song-card"; shot.lifetime = .keepAlways; add(shot)

        // Tapping empty space (no mode active) deselects the star and removes the card.
        // The map holds still, so try a spread of edge spots until one is clear of stars. They stay
        // off the top bar, the chip row, the right-hand rail and the readout, which would take the tap.
        let spots = [0.01, 0.03, 0.06, 0.1].flatMap { x in
            [0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65].map { CGVector(dx: x, dy: $0) }
        }
        for spot in spots where card.exists {
            app.coordinate(withNormalizedOffset: spot).tap()
            _ = card.waitForNonExistence(timeout: 2)
        }
        XCTAssertFalse(card.exists, "tapping empty space should dismiss the tray's track")
    }

    @MainActor
    func testSearchListFloatsAndTrayStaysClearOfRail() throws {
        waitForMap()
        let chip = chips.firstMatch
        let railBlend = app.buttons["vibe-rail-blend"]
        let chipY = chip.frame.minY, railY = railBlend.frame.minY
        let field = app.textFields["vibe-search"]
        field.tap()
        field.typeText("synthetic 12")
        XCTAssertTrue(app.staticTexts["vibe-search-summary"].waitForExistence(timeout: 5))
        XCTAssertFalse(chip.exists && chip.isHittable, "the list covers the chips, which hide in place")
        let row = app.buttons.matching(identifier: "vibe-search-result").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let tray = app.otherElements["vibe-tray"]
        let title = app.staticTexts["vibe-tray-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(chip.exists && chip.isHittable, "the chips hide while a star is selected")
        let lastRail = app.buttons["vibe-rail-blend"]
        let clear = app.buttons["vibe-clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(lastRail.frame.minX - tray.frame.maxX, 8, "the readout ends 8pt or more left of the rail")
        XCTAssertEqual(lastRail.frame.minY, railY, accuracy: 1, "selecting must not move the rail")
        // Back undoes the newest thing first: the selection, then the search. The chips come back
        // where they were.
        XCTAssertTrue(clear.label.hasPrefix("deselect "), clear.label)
        clear.tap()
        XCTAssertEqual(clear.label, "clear search")
        clear.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the chips come back once nothing is selected")
        XCTAssertEqual(chip.frame.minY, chipY, accuracy: 1, "the result list must not move the chips")
    }

    /// The rail's song path and blend sit in one place at rest, with a selection, with a panel open,
    /// after the help line returns, and with the mini player showing.
    @MainActor
    func testRailStaysPutAcrossStates() throws {
        waitForMap()
        let path = app.buttons["vibe-rail-songpath"], blend = app.buttons["vibe-rail-blend"]
        let pathFrame = path.frame, blendFrame = blend.frame
        func assertInPlace(_ state: String) {
            XCTAssertEqual(path.frame.minY, pathFrame.minY, accuracy: 1, "song path moved: \(state)")
            XCTAssertEqual(blend.frame.minY, blendFrame.minY, accuracy: 1, "blend moved: \(state)")
            XCTAssertEqual(blend.frame.minX, blendFrame.minX, accuracy: 1, "blend moved sideways: \(state)")
        }
        let star = app.otherElements["vibe-debug-star"]
        XCTAssertTrue(star.waitForExistence(timeout: 20), "no on-screen star to tap")
        star.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["vibe-tray-title"].waitForExistence(timeout: 5))
        assertInPlace("selected")
        blend.tap()
        XCTAssertTrue(app.textFields["vibe-blend-search"].waitForExistence(timeout: 5))
        assertInPlace("blend open")
        app.buttons["vibe-blend-more"].tap()
        XCTAssertTrue(app.buttons["vibe-blend-remove"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["vibe-blend-remove"].firstMatch.isHittable, "the panel's × is reachable")
        app.buttons["vibe-clear"].tap()
        XCTAssertTrue(app.textFields["vibe-blend-search"].waitForNonExistence(timeout: 5))
        assertInPlace("blend closed")

        app.terminate()
        app.launchArguments += ["-kima-fake-now-playing"]
        app.launch()
        waitForMap()
        assertInPlace("mini player showing")
    }

    @MainActor
    func testTopBarButtonsExist() throws {
        waitForMap()
        for id in ["vibe-close", "vibe-home", "vibe-labels"] {
            XCTAssertTrue(app.buttons[id].exists, "\(id) missing")
        }
        let labels = app.buttons["vibe-labels"]
        // The toggle persists on the simulator, so check it flips rather than what it starts as.
        let before = labels.label
        XCTAssertTrue(["show labels", "hide labels"].contains(before), before)
        labels.tap()
        let after = before == "show labels" ? "hide labels" : "show labels"
        XCTAssertEqual(app.buttons["vibe-labels"].label, after)
        app.buttons["vibe-labels"].tap()
        XCTAssertEqual(app.buttons["vibe-labels"].label, before)
    }

    @MainActor
    func testSearchListsMatchesAndPickSelectsTheTrack() throws {
        waitForMap()
        let field = app.textFields["vibe-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("synthetic 12")
        let summary = app.staticTexts["vibe-search-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "no result summary")
        XCTAssertTrue(summary.label.contains("match"), summary.label)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "vibe-search"; shot.lifetime = .keepAlways; add(shot)
        let row = app.buttons.matching(identifier: "vibe-search-result").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no result rows")
        row.tap()
        XCTAssertTrue(app.staticTexts["vibe-tray-title"].waitForExistence(timeout: 5), "picking a result should select it")
    }

    @MainActor
    func testRailOpensSongPathAndBlendPanels() throws {
        waitForMap()
        app.buttons["vibe-rail-songpath"].tap()
        XCTAssertTrue(app.textFields["vibe-path-start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["vibe-path-end"].exists, "one prompt at a time: the start first")
        XCTAssertFalse(app.buttons["vibe-path-generate"].isEnabled, "generate waits for both tracks")
        XCTAssertFalse(app.buttons["vibe-panel-close"].exists, "the rail's back is the one way out")
        app.buttons["vibe-clear"].tap()
        XCTAssertTrue(app.textFields["vibe-path-start"].waitForNonExistence(timeout: 5))

        app.buttons["vibe-rail-blend"].tap()
        XCTAssertTrue(app.textFields["vibe-blend-search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["vibe-blend-go"].isEnabled, "blend waits for a more-like track")
        XCTAssertFalse(app.buttons["vibe-blend-play"].exists, "nothing to play before a blend")
        app.buttons["vibe-clear"].tap()
        XCTAssertTrue(app.textFields["vibe-blend-search"].waitForNonExistence(timeout: 5))
    }

    /// With the keyboard up and the panel's list showing, the top bar stays where it was, the chips hide
    /// under the lifted panel and come back in place, the panel's field and action sit above the
    /// keyboard, and at least three results show.
    private func assertKeyboardLeavesTheTopBarInPlace(rail: String, field fieldId: String, action: String,
                                                      shot name: String) {
        waitForMap()
        let close = app.buttons["vibe-close"]
        let closeY = close.frame.minY, chipY = chips.firstMatch.frame.minY
        app.buttons[rail].tap()
        let field = app.textFields[fieldId]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("synthetic 5")
        XCTAssertTrue(app.buttons.matching(identifier: "vibe-finder-result").firstMatch.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        XCTAssertEqual(close.frame.minY, closeY, accuracy: 1, "the keyboard pushed the top bar")
        XCTAssertFalse(chips.firstMatch.exists && chips.firstMatch.isHittable, "the chips hide under the lifted panel")
        XCTAssertTrue(close.isHittable, "the top bar went off screen")
        XCTAssertTrue(field.isHittable, "the field is under the keyboard")
        XCTAssertTrue(app.buttons[action].isHittable, "\(action) is under the keyboard")
        let rows = app.buttons.matching(identifier: "vibe-finder-result").allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(rows.filter(\.isHittable).count, 3, "fewer than three results above the keyboard")
        app.buttons["dismiss keyboard"].tap()
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(chips.firstMatch.frame.minY, chipY, accuracy: 1, "the chips came back somewhere else")
    }

    @MainActor
    func testBlendKeyboardLeavesTheTopBarInPlace() throws {
        assertKeyboardLeavesTheTopBarInPlace(rail: "vibe-rail-blend", field: "vibe-blend-search", action: "vibe-blend-go",
                                             shot: "blend-keyboard")
    }

    @MainActor
    func testSongPathKeyboardLeavesTheTopBarInPlace() throws {
        assertKeyboardLeavesTheTopBarInPlace(rail: "vibe-rail-songpath", field: "vibe-path-start",
                                             action: "vibe-path-generate", shot: "songpath-keyboard")
    }
}
