import XCTest
@testable import Kima

/// `PlaybackController.isAudiobookLoaded(_:)`: true only for the audiobook in the player.
@MainActor
final class AudiobookLoadedTests: XCTestCase {
    private func makeController() -> PlaybackController {
        PlaybackController(server: KimaServer(baseURL: URL(string: "https://stub.test")!))
    }

    func testNothingLoaded() {
        XCTAssertFalse(makeController().isAudiobookLoaded("b"))
    }

    func testMatchesOnlyTheLoadedBook() {
        let c = makeController()
        c.playbackType = .audiobook(BookSession(bookId: "b", totalDuration: 100,
            files: [AudiobookTrack(index: 1, startOffset: 0, duration: 100)]))
        XCTAssertTrue(c.isAudiobookLoaded("b"))
        XCTAssertFalse(c.isAudiobookLoaded("other"))
    }
}
