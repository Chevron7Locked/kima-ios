import XCTest
@testable import Kima

final class QueueOriginTests: XCTestCase {
    func testHeaders() {
        XCTAssertEqual(QueueOrigin.songPath.header(trackCount: 12), "song path — 12 tracks")
        XCTAssertEqual(QueueOrigin.songPath.header(trackCount: 1), "song path — 1 track")
        XCTAssertEqual(QueueOrigin.playSimilar.header(trackCount: 51), "play similar — 51 tracks")
        XCTAssertEqual(QueueOrigin.blend.header(trackCount: 30), "blend — 30 tracks")
    }

    func testReplaceQuestionIsOnePlainSentence() {
        XCTAssertEqual(VibeReplacePrompt(current: .songPath, new: .playSimilar).question,
                       "replace the song path with similar tracks?")
        XCTAssertEqual(VibeReplacePrompt(current: .playSimilar, new: .songPath).question,
                       "replace the similar tracks with a song path?")
        XCTAssertEqual(VibeReplacePrompt(current: .blend, new: .blend).question,
                       "replace the blend with a new blend?")
    }
}
