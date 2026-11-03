import XCTest

/// Regression guard: players must not rest on "unknown artist". Playlist/library list shapes omit the top-level
/// `artist` (the server nests it under `album.artist`), so the mini player shows the fallback until
/// `hydrateCurrentTrackCoverIfNeeded` fetches the track detail. Plays a playlist and asserts the mini player settles on a
/// real artist line. Needs the simulator's saved session and a non-empty playlist; skips with a screenshot when absent.
/// Each test plays, so the account's saved queue is saved first and put back after.
final class PlayerArtistHydrationUITests: XCTestCase {
    private var app: XCUIApplication!
    private var queueSaved = false

    override func setUpWithError() throws {
        continueAfterFailure = true
        let line = serverState("snapshot", "queue")
        guard line.hasPrefix("saved:") else { throw XCTSkip("play queue not saved first, so not changed: \(line)") }
        queueSaved = true
        app = XCUIApplication()
    }

    override func tearDown() {
        guard queueSaved else { return }
        app?.terminate()
        let line = serverState("restore", "queue")
        XCTAssertTrue(line.hasPrefix("restored:"), "play queue not put back: \(line)")
    }

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways
        add(a)
    }

    @MainActor
    func testPlaylistPlayAllShowsRealArtist() throws {
        // `-kima-open playlist` lands on the Playlists tab and auto-pushes the
        // first loaded playlist (PlaylistsListView DEBUG hook).
        app.launchArguments = ["-kima-open", "playlist"]
        app.launch()

        let playAll = app.buttons["playlist-play-all"]
        if !playAll.waitForExistence(timeout: 30) {
            // Fallback for slower chain timing: the grid cards aggregate
            // "…N songs" into their button label — tap the first manually.
            let card = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "song")
            ).firstMatch
            guard card.waitForExistence(timeout: 10) else {
                attach("hydration-no-session")
                throw XCTSkip("no saved session / playlists on this sim")
            }
            card.tap()
        }
        XCTAssertTrue(playAll.waitForExistence(timeout: 20), "playlist detail / play-all never rendered")
        playAll.tap()

        // Real playback evidence first: the transport flips to "pause"
        // (MiniPlayerBar playButtonA11y, :380 — lowercase, distinct from the
        // full player's "Pause" control label).
        let transport = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "pause")).firstMatch
        XCTAssertTrue(transport.waitForExistence(timeout: 40),
                      "play-all never started playback (pause transport never appeared)")

        // The mini player's stable hook is `expand-player`; its combined a11y
        // label is "title, artist" (MiniPlayerBar.swift:236-238). Artist starts
        // nil for playlist queues and settles via the detail hydration fetch —
        // poll for the fallback string to disappear.
        let mini = app.descendants(matching: .any)
            .matching(identifier: "expand-player").firstMatch
        XCTAssertTrue(mini.waitForExistence(timeout: 30), "mini player never appeared")
        var label = mini.label
        for _ in 0..<8 {
            if !label.lowercased().contains("unknown artist") && label.contains(",") { break }
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            label = mini.label
        }
        attach("playlist-playall-mini")
        XCTAssertFalse(label.lowercased().contains("unknown artist"),
                       "mini player pinned to the fallback: '\(label)'")
        XCTAssertTrue(label.contains(","), "no artist line in mini label: '\(label)'")
    }

    /// Regression guard — "unknown artist after auto-skip". `-kima-open skip-missing`
    /// (HomeView DEBUG hook → PlaybackController.debugPlayMissingThenReal) plays a bare shuffle
    /// track, then queues an unplayable id in front of a fresh bare copy of it. The 404 drives the
    /// failure policy's skip; the mini player must land on the real artist, not the fallback.
    @MainActor
    func testSkipPastMissingTrackShowsRealArtist() throws {
        app.launchArguments = ["-kima-open", "skip-missing"]
        app.launch()

        // Round 2 has started once its marker toast shows, or once the unplayable id's skip notice replaces that
        // toast (it can within a second, before a poll sees it). Nothing before that is asserted on.
        let round2 = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
            "skip-missing round 2", "no longer on your server")).firstMatch
        guard round2.waitForExistence(timeout: 45) else {
            attach("skip-missing-no-round2")
            throw XCTSkip("no saved session / library tracks on this sim (round 2 never started)")
        }

        let mini = app.descendants(matching: .any)
            .matching(identifier: "expand-player").firstMatch
        XCTAssertTrue(mini.waitForExistence(timeout: 10), "mini player never appeared")
        // 404 ladder (3 rebuilds) → skip → detail fill. Poll for the settled state.
        var label = mini.label
        for _ in 0..<15 {
            let l = label.lowercased()
            if !l.contains("missing track") && !l.contains("unknown artist") && l.contains(",") { break }
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            label = mini.label
        }
        attach("skip-missing-mini")
        XCTAssertFalse(label.lowercased().contains("missing track"),
                       "failure policy never skipped past the unplayable id: '\(label)'")
        XCTAssertFalse(label.lowercased().contains("unknown artist"),
                       "skipped-to track pinned to the fallback: '\(label)'")
    }

    /// Gone-track skipping — `-kima-open skip-gone` (HomeView DEBUG hook →
    /// PlaybackController.debugPlayThreeMissingThenReal) queues three unplayable ids in front of
    /// a real track. Each must be dropped with a notice and WITHOUT counting toward the
    /// three-failures-in-a-row full stop: the real track plays and the mini player stays.
    @MainActor
    func testThreeGoneTracksSkipToRealTrackAndKeepQueue() throws {
        app.launchArguments = ["-kima-open", "skip-gone"]
        app.launch()

        let mini = app.descendants(matching: .any)
            .matching(identifier: "expand-player").firstMatch
        guard mini.waitForExistence(timeout: 45) else {
            attach("skip-gone-no-session")
            throw XCTSkip("no saved session / library tracks on this sim (nothing was queued)")
        }

        let notice = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS[c] %@", "no longer on your server")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 20),
                      "no skip notice — gone tracks were not detected")

        let playing = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "pause")).firstMatch
        var label = mini.exists ? mini.label : ""
        for _ in 0..<15 {
            if mini.exists, !label.lowercased().contains("missing track"), playing.exists { break }
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            label = mini.exists ? mini.label : ""
        }
        attach("skip-gone-mini")
        XCTAssertTrue(mini.exists, "queue was cleared — the mini player is gone")
        XCTAssertFalse(label.lowercased().contains("missing track"),
                       "still on an unplayable id: '\(label)'")
        XCTAssertTrue(playing.exists, "the real track never started playing")
    }
}
