import XCTest
@testable import Kima

/// The library's mood marks: each song's mood, an album's or artist's main mood, and the mood band's shares.
final class LibraryMoodsTests: XCTestCase {

    private func track(_ id: String, _ mood: String, album: String = "al", artist: String = "ar") -> VibeMapTrack {
        VibeMapTrack(id: id, x: 0.5, y: 0.5, title: id, artist: "a", artistId: artist, albumId: album,
                     coverUrl: nil, dominantMood: mood, moodScore: 0.5, moods: [:], energy: nil, valence: nil)
    }

    func testSongsCarryOnlyTheFiveMoods() {
        let m = LibraryMoods(tracks: [track("a", "moodSad"), track("b", "neutral"), track("c", "unanalyzed"),
                                      track("d", "relaxed"), track("e", "moodElectronic")])
        XCTAssertEqual(m.trackMood["a"], "moodSad")
        XCTAssertEqual(m.trackMood["d"], "moodRelaxed", "bare axis names map to the palette key")
        XCTAssertNil(m.trackMood["b"])
        XCTAssertNil(m.trackMood["c"])
        XCTAssertNil(m.trackMood["e"], "a sound axis is not a mood")
    }

    func testAlbumTakesTheMoodMostSongsShare() {
        let m = LibraryMoods(tracks: [track("a", "moodSad"), track("b", "moodSad"), track("c", "moodParty"),
                                      track("x", "neutral", album: "quiet"), track("y", "neutral", album: "quiet"),
                                      track("z", "moodHappy", album: "quiet")])
        XCTAssertEqual(m.albumMood["al"], "moodSad")
        XCTAssertNil(m.albumMood["quiet"], "mostly no single mood: no dot")
        XCTAssertEqual(m.artistMood["ar"], "moodSad")
    }

    func testTieGoesToTheLegendOrderAndMoodsBeatNeutral() {
        let m = LibraryMoods(tracks: [track("a", "moodParty"), track("b", "moodHappy"), track("c", "neutral"),
                                      track("d", "neutral", album: "t"), track("e", "moodSad", album: "t")])
        XCTAssertEqual(m.albumMood["al"], "moodHappy")
        XCTAssertEqual(m.albumMood["t"], "moodSad")
    }

    func testSharesAreOfAnalysedSongsBiggestFirstThenNeutral() throws {
        let m = LibraryMoods(tracks: [track("a", "moodSad"), track("b", "moodRelaxed"), track("c", "moodRelaxed"),
                                      track("d", "neutral"), track("e", "unanalyzed")])
        XCTAssertEqual(m.shares.map(\.key), ["moodRelaxed", "moodSad", "neutral"])
        XCTAssertEqual(try XCTUnwrap(m.shares.first).fraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.shares.map(\.fraction).reduce(0, +), 1, accuracy: 1e-9)
    }

    func testNothingAnalysedHasNoBand() {
        XCTAssertTrue(LibraryMoods(tracks: [track("a", "unanalyzed")]).shares.isEmpty)
        XCTAssertTrue(LibraryMoods.empty.shares.isEmpty)
    }
}
