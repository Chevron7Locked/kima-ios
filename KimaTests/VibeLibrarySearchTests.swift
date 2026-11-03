import XCTest
@testable import Kima

final class VibeLibrarySearchTests: XCTestCase {

    private func t(_ id: String, _ title: String, _ artist: String) -> VibeMapTrack {
        VibeMapTrack(id: id, x: 0, y: 0, title: title, artist: artist, artistId: "ar", albumId: "al",
                     coverUrl: nil, dominantMood: "happy", moodScore: 0.5, moods: [:], energy: nil, valence: nil)
    }

    private var index: VibeLibraryIndex {
        VibeLibraryIndex(tracks: [
            t("1", "Blue Monday", "New Order"),
            t("2", "Monday Blues", "Someone"),
            t("3", "Crème Brûlée", "Beyoncé"),
            t("4", "Order of Things", "Blue Band"),
            t("5", "Unrelated", "Nobody"),
        ])
    }

    func testShortQueryMatchesNothing() {
        XCTAssertEqual(VibeLibrarySearch.search(index, query: "b").count, 0)
        XCTAssertEqual(VibeLibrarySearch.search(index, query: "  b ").count, 0)
        XCTAssertEqual(VibeLibrarySearch.search(index, query: "").ids, [])
    }

    func testEveryWordMustAppear() {
        let m = VibeLibrarySearch.search(index, query: "blue order")
        XCTAssertEqual(m.ids, ["1", "4"])
        XCTAssertEqual(VibeLibrarySearch.search(index, query: "blue zzz").count, 0)
    }

    func testAccentsAndCaseAreIgnored() {
        XCTAssertEqual(VibeLibrarySearch.search(index, query: "BEYONCE").ids, ["3"])
        XCTAssertEqual(VibeLibrarySearch.search(index, query: "creme brulee").ids, ["3"])
        XCTAssertEqual(VibeLibrarySearch.search(index, query: "beyoncé").ids, ["3"])
    }

    func testWordStartMatchesRankFirst() {
        let idx = VibeLibraryIndex(tracks: [
            t("a", "Abandon", "Someone"),
            t("b", "Band Aid", "Someone"),
            t("c", "The Band", "Other"),
        ])
        let m = VibeLibrarySearch.search(idx, query: "band")
        XCTAssertEqual(m.ids, ["a", "b", "c"])
        XCTAssertEqual(m.top.map(\.id), ["b", "c", "a"], "word-start matches come before inside matches")
    }

    func testLimitAndCount() {
        let many = VibeLibraryIndex(tracks: (0..<20).map { t("\($0)", "Song \($0)", "Artist") })
        let m = VibeLibrarySearch.search(many, query: "song")
        XCTAssertEqual(m.count, 20)
        XCTAssertEqual(m.ids.count, 20)
        XCTAssertEqual(m.top.count, 8)
        XCTAssertEqual(VibeLibrarySearch.summary(m), "20 matches · showing 8")
    }

    func testSummaryWording() {
        XCTAssertNil(VibeLibrarySearch.summary(VibeLibrarySearch.search(index, query: "a")))
        XCTAssertEqual(VibeLibrarySearch.summary(VibeLibrarySearch.search(index, query: "zzzz")), "no tracks match “zzzz”")
        let one = VibeLibrarySearch.search(index, query: "unrelated")
        XCTAssertEqual(VibeLibrarySearch.summary(one), "1 match")
    }

    func testSummaryDescribesTheQueryTheMatchesAnswer() {
        let older = VibeLibrarySearch.search(index, query: "blue")
        XCTAssertEqual(older.query, "blue")
        XCTAssertEqual(VibeLibrarySearch.summary(older), "3 matches")
        XCTAssertEqual(VibeLibrarySearch.summary(VibeLibrarySearch.search(index, query: "bluez")), "no tracks match “bluez”")
    }

    func testSameTitleResultsFromDifferentAlbumsShowTheirAlbum() {
        func a(_ id: String, _ title: String, album: String) -> VibeMapTrack {
            VibeMapTrack(id: id, x: 0, y: 0, title: title, artist: "Chvrches", artistId: "ar", albumId: album,
                         coverUrl: nil, dominantMood: "happy", moodScore: 0.5, moods: [:], energy: nil, valence: nil)
        }
        let list = [a("1", "Bury It", album: "a1"), a("2", "bury it", album: "a2"),
                    a("3", "Recover", album: "a1"), a("4", "Lustration", album: "a3"), a("5", "Lustration", album: "a3")]
        let toName = VibeLibrarySearch.albumsToName(list)
        XCTAssertEqual(Set(toName.keys), ["a1", "a2"], "a repeat on one album has nothing to name")
        XCTAssertEqual(toName["a1"], "1", "each album is looked up through one of its own tracks")
        XCTAssertEqual(toName["a2"], "2")
        let names = ["a1": "The Bones of What You Believe", "a2": "Every Open Eye"]
        XCTAssertEqual(VibeLibrarySearch.detail(for: list[0], among: list, albumTitles: names),
                       "Chvrches · The Bones of What You Believe")
        XCTAssertEqual(VibeLibrarySearch.detail(for: list[1], among: list, albumTitles: [:]), "Chvrches",
                       "the artist alone until the album's name is known")
        XCTAssertEqual(VibeLibrarySearch.detail(for: list[2], among: list, albumTitles: names), "Chvrches")
        XCTAssertEqual(VibeLibrarySearch.detail(for: list[3], among: list, albumTitles: names), "Chvrches")
    }

    func testSameTitleFromDifferentArtistsNeedsNoAlbum() {
        func a(_ id: String, _ title: String, by artist: String, album: String) -> VibeMapTrack {
            VibeMapTrack(id: id, x: 0, y: 0, title: title, artist: artist, artistId: artist, albumId: album,
                         coverUrl: nil, dominantMood: "happy", moodScore: 0.5, moods: [:], energy: nil, valence: nil)
        }
        let covers = [a("1", "Hurt", by: "Nine Inch Nails", album: "a1"), a("2", "Hurt", by: "Johnny Cash", album: "a2")]
        XCTAssertTrue(VibeLibrarySearch.albumsToName(covers).isEmpty, "the artist already tells them apart")
        XCTAssertEqual(VibeLibrarySearch.detail(for: covers[0], among: covers, albumTitles: ["a1": "The Downward Spiral"]),
                       "Nine Inch Nails")
        let sameArtist = [a("1", "Hurt", by: "Johnny Cash", album: "a1"), a("2", "hurt", by: "johnny cash", album: "a2")]
        XCTAssertEqual(Set(VibeLibrarySearch.albumsToName(sameArtist).keys), ["a1", "a2"],
                       "title and artist collide, ignoring case")
    }
}
