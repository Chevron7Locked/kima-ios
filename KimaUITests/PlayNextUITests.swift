import XCTest

/// Play Next wiring: the context-menu "play next" item on an album track row inserts the track and the shared toast
/// (`announcePlayNext`, TrackTransferable.swift) confirms it. Reaches the first album via `-kima-open album` and uses
/// its first track, so it runs on any library; the session must already exist. The account's saved queue is saved
/// first and put back after.
final class PlayNextUITests: XCTestCase {

    private var queueSaved = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        let line = serverState("snapshot", "queue")
        guard line.hasPrefix("saved:") else { throw XCTSkip("play queue not saved first, so not changed: \(line)") }
        queueSaved = true
    }

    override func tearDown() {
        guard queueSaved else { return }
        let line = serverState("restore", "queue")
        XCTAssertTrue(line.hasPrefix("restored:"), "play queue not put back: \(line)")
    }

    @MainActor
    func testAlbumTrackContextMenuShowsPlayNextAndConfirmsWithToast() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-kima-open", "album"]
        app.launch()

        // The deep link pushed the first album: wait for its first track you own.
        let trackRow = app.buttons.matching(identifier: "album-track").firstMatch
        if !trackRow.waitForExistence(timeout: 30) {
            attachScreenshot("playnext-no-track")
            throw XCTSkip("the first album has no track you own (or the album never opened)")
        }

        // Long-press opens the track context menu (play / play next / add to queue / …).
        trackRow.press(forDuration: 1.2)
        let playNextItem = app.buttons["play next"]
        XCTAssertTrue(
            playNextItem.waitForExistence(timeout: 10),
            "Context menu did not offer a 'play next' item on an owned album track row"
        )
        playNextItem.tap()

        // Shared toast confirms the outcome: "playing next" with music loaded, else "started playback".
        let confirmed = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "playing next", "started playback")).firstMatch
        XCTAssertTrue(
            confirmed.waitForExistence(timeout: 8),
            "No confirmation toast after 'play next' — handler did not run or announcePlayNext copy diverged"
        )
        attachScreenshot("playnext-toast")
    }
}
