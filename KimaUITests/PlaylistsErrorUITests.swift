import XCTest

/// A failed playlists load must say so, not claim the user has no playlists.
/// The fake signed-in session points at a refused server (127.0.0.1:9), so no real server is needed.
final class PlaylistsErrorUITests: XCTestCase {
    @MainActor
    func testPlaylistsLoadFailureShowsErrorNotEmpty() {
        let app = XCUIApplication()
        app.launchArguments = ["-kima-fake-signed-in", "-kima-open", "playlist"]
        app.launch()

        XCTAssertTrue(app.staticTexts["couldn't load playlists"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["try again"].exists)
        XCTAssertFalse(app.staticTexts["create your first playlist"].exists)
    }
}
