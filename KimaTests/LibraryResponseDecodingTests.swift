import XCTest
@testable import Kima

final class LibraryResponseDecodingTests: XCTestCase {
    func testOneBadRowKeepsTheRestOfThePage() throws {
        let json = #"{"albums":[{"id":"a1","title":"good"},{"id":"a2","title":null},{"id":"a3","title":"also good"}],"total":3}"#
        let page = try JSONDecoder().decode(AlbumsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(page.albums.map(\.id), ["a1", "a3"])
        XCTAssertEqual(page.total, 3)
    }

    func testBadArtistAndTrackRowsAreDropped() throws {
        let artists = #"{"artists":[{"id":"r1","name":"ok"},{"id":"r2"}]}"#
        XCTAssertEqual(try JSONDecoder().decode(ArtistsResponse.self, from: Data(artists.utf8)).artists.map(\.id), ["r1"])
        let tracks = #"{"tracks":[{"id":"t1","title":"ok","duration":1},{"title":"no id","duration":1}],"total":2}"#
        XCTAssertEqual(try JSONDecoder().decode(TracksResponse.self, from: Data(tracks.utf8)).tracks.map(\.id), ["t1"])
    }

    func testMissingListStillFails() {
        XCTAssertThrowsError(try JSONDecoder().decode(AlbumsResponse.self, from: Data(#"{"total":3}"#.utf8)))
    }

    /// Library and search send a song's artist inside its album; the row reads it from there.
    func testTrackFallsBackToItsAlbumsArtist() throws {
        let json = #"{"id":"t1","title":"song","duration":1,"album":{"id":"a1","title":"record","coverArt":"c","artist":{"id":"r1","name":"the band"}}}"#
        let track = try JSONDecoder().decode(Track.self, from: Data(json.utf8))
        XCTAssertEqual(track.artist?.name, "the band")
        XCTAssertEqual(track.artist?.id, "r1")
    }

    func testTrackPrefersItsOwnArtist() throws {
        let json = #"{"id":"t1","title":"song","duration":1,"artist":{"id":"r2","name":"guest"},"album":{"id":"a1","title":"record","coverArt":null,"artist":{"id":"r1","name":"the band"}}}"#
        let track = try JSONDecoder().decode(Track.self, from: Data(json.utf8))
        XCTAssertEqual(track.artist?.name, "guest")
        // Encoding keeps the song's own artist under "artist", so a saved queue decodes the same.
        let again = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(track))
        XCTAssertEqual(again.artist?.name, "guest")
    }

    /// The artist page's Popular section is global popularity now, and the server joins it against
    /// the library: a hot track you do not own arrives with a `dz:` id, a signed Deezer preview URL,
    /// global play/listener counts, and an album with no id. The row previews it; an owned hot track
    /// keeps its library id and plays.
    func testGlobalPopularRowsDecodeForOwnedAndUnowned() throws {
        let unowned = """
        {"id":"dz:648c7d5b-9c5b-4c1a-9c34-0a5b6f1a2b3c","title":"Creep","duration":237,
         "playCount":4390914,"listeners":209990,"userPlayCount":0,"popularitySource":"global",
         "previewUrl":"https://cdn.dz.example/preview.m4a",
         "album":{"id":null,"title":"Pablo Honey","coverUrl":null}}
        """
        let hot = try JSONDecoder().decode(Track.self, from: Data(unowned.utf8))
        XCTAssertEqual(hot.id, "dz:648c7d5b-9c5b-4c1a-9c34-0a5b6f1a2b3c")
        XCTAssertEqual(hot.playCount, 4_390_914)
        XCTAssertEqual(hot.listeners, 209_990)
        XCTAssertEqual(hot.userPlayCount, 0)
        XCTAssertNotNil(hot.previewUrl)
        // The artist screen calls a track unowned when its album has no id.
        XCTAssertNil(hot.album?.id)

        let owned = """
        {"id":"t1","title":"Creep","duration":237,"playCount":4390914,"listeners":209990,
         "userPlayCount":7,"album":{"id":"a1","title":"Pablo Honey","coverArt":"c1"}}
        """
        let mine = try JSONDecoder().decode(Track.self, from: Data(owned.utf8))
        XCTAssertEqual(mine.album?.id, "a1")
        XCTAssertEqual(mine.userPlayCount, 7)
    }

    /// Playing and queueing an album both use disc, then track order, whatever order the server sent.
    func testAlbumTracksPlayInDiscThenTrackOrder() throws {
        let json = #"{"id":"a1","title":"record","tracks":[{"id":"d2t1","title":"x","duration":1,"discNumber":2,"trackNo":1},{"id":"d1t2","title":"x","duration":1,"discNumber":1,"trackNo":2},{"id":"none","title":"x","duration":1},{"id":"d1t1","title":"x","duration":1,"trackNo":1}]}"#
        let album = try JSONDecoder().decode(Album.self, from: Data(json.utf8))
        XCTAssertEqual(album.tracksInOrder.map(\.id), ["d1t1", "d1t2", "none", "d2t1"])
    }
}
