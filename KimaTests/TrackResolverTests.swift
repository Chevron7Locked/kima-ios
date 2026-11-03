import XCTest
@testable import Kima

final class TrackResolverTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset() }

    func testFailedAlbumIsCountedAndTheRestStillResolve() async throws {
        StubURLProtocol.handler = { req in
            switch req.url?.path ?? "" {
            case "/api/library/albums/a1":
                return (200, Data(#"{"id":"a1","title":"one","tracks":[{"id":"t1","title":"song","duration":1}]}"#.utf8))
            default:
                return (500, Data())
            }
        }
        let artist = try JSONDecoder().decode(Artist.self, from: Data(#"""
        {"id":"ar1","name":"x","albums":[
          {"id":"a1","title":"one","owned":true,"year":2020},
          {"id":"a2","title":"two","owned":true,"year":2019},
          {"id":"a3","title":"not owned","owned":false,"year":2021}]}
        """#.utf8))
        let resolved = await KimaAPIClient.stubbed().ownedTracks(of: artist)
        XCTAssertEqual(resolved.tracks.map(\.id), ["t1"])
        XCTAssertEqual(resolved.failedAlbums, 1)
    }

    func testCouldntLoadText() {
        XCTAssertEqual(couldntLoadAlbumsText(1), "couldn't load 1 album")
        XCTAssertEqual(couldntLoadAlbumsText(3), "couldn't load 3 albums")
    }
}
