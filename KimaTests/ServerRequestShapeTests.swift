import XCTest
@testable import Kima

/// What the app sends: the listener's time zone on mix requests, a station page's query, and the sample stream URL.
@MainActor
final class ServerRequestShapeTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset() }

    private func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testEveryMixRequestCarriesTheTimeZone() async throws {
        StubURLProtocol.handler = { req in
            switch req.url!.path {
            case let p where p.hasSuffix("/mixes/refresh"): return (200, Data(#"{"message":"ok","mixes":[]}"#.utf8))
            case let p where p.hasSuffix("/mixes"): return (200, Data("[]".utf8))
            default: return (200, Data(#"{"tracks":[]}"#.utf8))
            }
        }
        let client = KimaAPIClient.stubbed()
        _ = try await client.getMixes()
        _ = try await client.getMixTracks(id: "m1")
        _ = try await client.refreshMixes()
        XCTAssertEqual(StubURLProtocol.requests.count, 3)
        for request in StubURLProtocol.requests {
            XCTAssertEqual(query(request)["tz"], TimeZone.current.identifier, request.url!.absoluteString)
        }
    }

    func testIdsAreSentAsOnePathSegment() async throws {
        StubURLProtocol.handler = { req in
            req.httpMethod == "PATCH" ? (200, Data(#"{"id":"p","name":"n"}"#.utf8)) : (200, Data(#"{"tracks":[]}"#.utf8))
        }
        let client = KimaAPIClient.stubbed()
        _ = try await client.getMixTracks(id: "a/b?c#d")
        try await client.setPlaylistReverseOrder(id: "a/b?c#d", reversed: true)
        let paths = StubURLProtocol.requests.compactMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.percentEncodedPath }
        XCTAssertEqual(paths, ["/api/mixes/a%2Fb%3Fc%23d", "/api/playlists/a%2Fb%3Fc%23d"])
        XCTAssertEqual(StubURLProtocol.requests.last?.httpMethod, "PATCH")
    }

    func testRadioPageQuery() async throws {
        StubURLProtocol.handler = { _ in (200, Data(#"{"tracks":[],"next":100}"#.utf8)) }
        let page = try await KimaAPIClient.stubbed().getRadioPage(
            type: "mood", value: "late-night", limit: 100, seed: "abc", offset: 100, tz: "Europe/Paris")
        XCTAssertEqual(page.next, 100)
        let q = query(try XCTUnwrap(StubURLProtocol.requests.first))
        XCTAssertEqual(q, ["type": "mood", "value": "late-night", "limit": "100", "seed": "abc", "offset": "100",
                           "tz": "Europe/Paris"])
        XCTAssertTrue(StubURLProtocol.requests[0].url!.path.hasSuffix("/api/library/radio"))
    }

    func testPodcastSnippetURL() throws {
        let url = try XCTUnwrap(StreamURL.podcastSnippet(
            base: KimaServer(baseURL: URL(string: "https://k.test")!), itunesId: "1200361736", token: "t"))
        XCTAssertEqual(url.absoluteString, "https://k.test/api/podcasts/preview/1200361736/snippet?token=t")
    }

    func testNumericItunesIdWithChartFields() throws {
        let show = try JSONDecoder().decode(DiscoveryPodcast.self, from: Data(#"""
        {"id":"9","itunesId":9,"title":"t","author":"a","description":"d","coverUrl":null,"feedUrl":null,
         "genres":[],"categoryIds":[1303],"episodeCount":0,"chartRank":3,"isExternal":true}
        """#.utf8))
        XCTAssertEqual(show.itunesId, "9")
        XCTAssertEqual(show.chartRank, 3)
        XCTAssertEqual(show.categoryIds, [1303])
    }

    func testFittedMosaicFramesAndFailedCovers() {
        let view = PlaylistMosaicView(coverIds: ["a", "b", "c"], fitsCovers: true)
        XCTAssertEqual(view.fittedCovers(excluding: ["b"]), ["a", "c"])
        let three = PlaylistMosaicView.fittedFrames(count: 3)
        XCTAssertEqual(three.map(\.h), [1, 0.5, 0.5], "one tall and two small")
        XCTAssertEqual(three.map(\.x), [0, 0.5, 0.5])
        XCTAssertEqual(PlaylistMosaicView.fittedFrames(count: 2).map(\.w), [0.5, 0.5])
        XCTAssertEqual(PlaylistMosaicView.fittedFrames(count: 4).map(\.y), [0, 0, 0.5, 0.5])
        let covered = PlaylistMosaicView.fittedFrames(count: 4).reduce(0) { $0 + $1.w * $1.h }
        XCTAssertEqual(covered, 1, "four cells cover the tile exactly")
    }
}

/// A mood station tile shows its first distinct albums (three at most) and its distinct artists, in play order.
final class StationPreviewTests: XCTestCase {
    private func track(_ id: String, album: String?, cover: String?, artist: String?) -> Track {
        Track(id: id, title: "t", duration: 1, artist: artist.map { TrackArtistRef(id: nil, name: $0) },
              album: TrackAlbumRef(id: album, title: nil, coverArt: cover))
    }

    func testCoversAreDistinctAlbumsAndArtistsAreDistinctNames() {
        let p = StationPreview(tracks: [
            track("1", album: "a", cover: "ca", artist: "Joep Beving"),
            track("2", album: "a", cover: "ca", artist: "joep beving"),
            track("3", album: "b", cover: nil, artist: "Ludovico Einaudi"),
            track("4", album: "c", cover: "cc", artist: "Max Richter"),
            track("5", album: "d", cover: "cd", artist: "Nils Frahm"),
            track("6", album: "e", cover: "ce", artist: nil),
        ])
        XCTAssertEqual(p.covers, ["ca", "cc", "cd"])
        XCTAssertEqual(p.artists, ["Joep Beving", "Ludovico Einaudi", "Max Richter", "Nils Frahm"])
        XCTAssertEqual(p.artistLines, ["Joep Beving, Ludovico Einaudi, Max Richter…",
                                       "Joep Beving, Ludovico Einaudi…", "Joep Beving…"])
    }

    func testAlbumsWithoutAnIdAreToldApartByCoverAndEmptyCoversSkipped() {
        let p = StationPreview(tracks: [
            track("1", album: nil, cover: "x", artist: "A"),
            track("2", album: nil, cover: "x", artist: "A"),
            track("3", album: "b", cover: "", artist: "B"),
            track("4", album: "c", cover: "x", artist: "C"),
        ])
        XCTAssertEqual(p.covers, ["x", "x"], "a different album with the same cover id still counts")
    }

    func testFewSongsGiveFewCoversAndNoEllipsis() {
        let one = StationPreview(tracks: [track("1", album: "a", cover: "ca", artist: "Solo")])
        XCTAssertEqual(one.covers, ["ca"])
        XCTAssertEqual(one.artistLines, ["Solo"])
        let none = StationPreview(tracks: [])
        XCTAssertTrue(none.covers.isEmpty)
        XCTAssertTrue(none.artistLines.isEmpty)
    }
}
