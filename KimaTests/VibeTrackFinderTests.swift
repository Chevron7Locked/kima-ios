import XCTest
@testable import Kima

final class VibeTrackFinderTests: XCTestCase {

    private func mapTrack(_ id: String, _ title: String, _ artist: String) -> VibeMapTrack {
        VibeMapTrack(id: id, x: 0, y: 0, title: title, artist: artist, artistId: "ar", albumId: "al",
                     coverUrl: nil, dominantMood: "moodSad", moodScore: 0.5, moods: [:],
                     energy: nil, valence: nil, colour: nil)
    }

    func testActiveNeedsTwoLetters() {
        XCTAssertFalse(VibeTrackFinder.isActive(" a "))
        XCTAssertFalse(VibeTrackFinder.isActive(""))
        XCTAssertTrue(VibeTrackFinder.isActive("ab"))
    }

    func testNameMatchesKeepOrderAndDetails() {
        let named = [mapTrack("1", "Rain", "A"), mapTrack("2", "Snow", "B")]
        let items = VibeTrackFinder.merge(byName: named, bySound: [], limit: 10)
        XCTAssertEqual(items.map(\.id), ["1", "2"])
        XCTAssertTrue(items.allSatisfy { !$0.viaSound })
        XCTAssertEqual(items[0].title, "Rain")
        XCTAssertEqual(items[0].detail, "A")
    }

    func testLimitCapsTheList() {
        let named = (0..<5).map { mapTrack("\($0)", "t\($0)", "a") }
        XCTAssertEqual(VibeTrackFinder.merge(byName: named, bySound: [], limit: 3).count, 3)
    }
}
