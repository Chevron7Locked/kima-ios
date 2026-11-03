import XCTest
@testable import Kima

/// The saved queue keeps each song's artist, including songs whose list only named the album's artist.
final class QueueTrackTests: XCTestCase {

    private func track(_ json: String) throws -> Track {
        try JSONDecoder().decode(Track.self, from: Data(json.utf8))
    }

    func testAlbumArtistIsSavedWhenTheTrackHasNone() throws {
        let t = try track(#"{"id":"t1","title":"be with you","duration":200,"album":{"id":"al","title":"x","coverArt":"c","artist":{"id":"ar","name":"cryogen"}}}"#)
        let q = QueueTrack(t)
        XCTAssertEqual(q.artist?.id, "ar")
        XCTAssertEqual(q.artist?.name, "cryogen")
        XCTAssertEqual(q.album?.coverArt, "c")
    }

    func testTheTracksOwnArtistWins() throws {
        let t = try track(#"{"id":"t1","title":"a","duration":1,"artist":{"id":"own","name":"own"},"album":{"id":"al","title":"x","artist":{"id":"ar","name":"album artist"}}}"#)
        XCTAssertEqual(QueueTrack(t).artist?.name, "own")
    }

    func testRestoredTrackShowsTheArtist() throws {
        let t = try track(#"{"id":"t1","title":"a","duration":1,"album":{"id":"al","title":"x","artist":{"id":"ar","name":"cryogen"}}}"#)
        let data = try JSONEncoder().encode([QueueTrack(t)])
        let restored = try JSONDecoder().decode([Track].self, from: data)
        XCTAssertEqual(restored.first?.artist?.name, "cryogen")
    }

    func testNoArtistAnywhereStaysEmpty() throws {
        let t = try track(#"{"id":"t1","title":"a","duration":1}"#)
        XCTAssertNil(QueueTrack(t).artist)
        XCTAssertNil(QueueTrack(t).album)
    }
}
