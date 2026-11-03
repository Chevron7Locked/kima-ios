import XCTest
@testable import Kima

final class DiscoveryPodcastDecodingTests: XCTestCase {
    private func decode(_ itunes: String) throws -> DiscoveryPodcast {
        let json = #"{"id":"1","title":"t","author":"a","coverUrl":null,"feedUrl":null,"genres":[],"episodeCount":0,"itunesId":\#(itunes),"isExternal":true}"#
        return try JSONDecoder().decode(DiscoveryPodcast.self, from: Data(json.utf8))
    }

    func testItunesIdAsString() throws {
        XCTAssertEqual(try decode(#""123""#).itunesId, "123")
    }

    func testItunesIdAsNumber() throws {
        XCTAssertEqual(try decode("123").itunesId, "123")
    }

    func testItunesIdNull() throws {
        XCTAssertNil(try decode("null").itunesId)
    }
}
