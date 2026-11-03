import XCTest
@testable import Kima

/// Artist tiles say how many albums, fall back to tracks, and hide the line when neither is known.
final class ArtistCountLabelTests: XCTestCase {
    private func artist(_ fields: String) throws -> Artist {
        let json = #"{"id":"a1","name":"some artist"\#(fields)}"#
        return try JSONDecoder().decode(Artist.self, from: Data(json.utf8))
    }

    func testAlbumCountWins() throws {
        XCTAssertEqual(ArtistsGridView.albumCountLabel(try artist(#","albumCount":3,"trackCount":30"#)), "3 albums")
        XCTAssertEqual(ArtistsGridView.albumCountLabel(try artist(#","albumCount":1"#)), "1 album")
    }

    func testZeroAlbumsFallsBackToTracks() throws {
        XCTAssertEqual(ArtistsGridView.albumCountLabel(try artist(#","albumCount":0,"trackCount":12"#)), "12 tracks")
        XCTAssertEqual(ArtistsGridView.albumCountLabel(try artist(#","albumCount":0,"trackCount":1"#)), "1 track")
    }

    func testNothingKnownHidesTheLine() throws {
        XCTAssertNil(ArtistsGridView.albumCountLabel(try artist(#","albumCount":0,"trackCount":0"#)))
        XCTAssertNil(ArtistsGridView.albumCountLabel(try artist("")))
    }
}
