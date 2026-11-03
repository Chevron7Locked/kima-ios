import XCTest
@testable import Kima

/// Play All / Shuffle All on the artist page.
///
/// The queue comes from `GET /api/library/artists/:id/play-tracks` in one request. These tests pin
/// that contract: one request, the server's order, no request at all when the artist owns nothing.
@MainActor
final class ArtistDetailPlayAllTests: XCTestCase {

    override func tearDown() { StubURLProtocol.reset() }

    /// Two tracks, deliberately not in track-number order: the client must pass the server's order
    /// through untouched, not re-sort by `trackNo`.
    private static let playTracksPayload = """
    {"artist":{"id":"art1","name":"ABBA"},"tracks":[
      {"id":"t1","title":"Dancing Queen","duration":250,"trackNo":2,"discNumber":1,
       "album":{"id":"alb1","title":"Arrival","coverArt":"/cover/1"}},
      {"id":"t2","title":"When I Passed the Door","duration":230,"trackNo":1,"discNumber":1,
       "album":{"id":"alb1","title":"Arrival","coverArt":"/cover/1"}}]}
    """

    private func artist(withOwnedAlbum owned: Bool) throws -> Artist {
        let flag = owned ? "true" : "false"
        return try JSONDecoder().decode(Artist.self, from: Data(
            #"{"id":"art1","name":"ABBA","albums":[{"id":"alb1","title":"Arrival","year":1976,"owned":\#(flag)}]}"#.utf8))
    }

    private func makePlayback() -> PlaybackController {
        PlaybackController(server: KimaServer(baseURL: URL(string: "https://stub.test")!))
    }

    func testPlayAllAsksTheServerForTheQueueInOneRequest() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (200, Data(Self.playTracksPayload.utf8)) }
        let vm = ArtistDetailViewModel()
        let player = makePlayback()

        try await vm.playAll(artist: artist(withOwnedAlbum: true),
                            client: KimaAPIClient.stubbed(), player: player, toast: ToastCenter())

        XCTAssertEqual(StubURLProtocol.requests.count, 1,
                       "Play All made more than one request to build the artist's queue")
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/api/library/artists/art1/play-tracks",
                       "Play All did not use the lean play-tracks endpoint")
        XCTAssertEqual(player.queue.map(\.id), ["t1", "t2"],
                       "the queue was reordered by the client instead of taken as the server sent it")
        XCTAssertTrue(vm.isLoadingAction == false, "the action is still marked in flight after it finished")
    }

    func testShuffleAllPlaysTheSameQueueShuffled() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (200, Data(Self.playTracksPayload.utf8)) }
        let vm = ArtistDetailViewModel()
        let player = makePlayback()

        try await vm.shuffleAll(artist: artist(withOwnedAlbum: true),
                                client: KimaAPIClient.stubbed(), player: player, toast: ToastCenter())

        XCTAssertEqual(Set(player.queue.map(\.id)), ["t1", "t2"], "shuffle lost a track")
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testPlayAllOnAnArtistWithNothingOwnedRequestsNothing() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (200, Data(Self.playTracksPayload.utf8)) }
        let vm = ArtistDetailViewModel()
        let player = makePlayback()
        let toast = ToastCenter()

        try await vm.playAll(artist: artist(withOwnedAlbum: false),
                            client: KimaAPIClient.stubbed(), player: player, toast: toast)

        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "a request ran for an artist with nothing owned")
        XCTAssertTrue(player.queue.isEmpty)
        XCTAssertNil(toast.current)
    }

    func testPlayAllFailureIsReportedNotSwallowed() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (500, Data(#"{"error":"boom"}"#.utf8)) }
        let vm = ArtistDetailViewModel()
        let toast = ToastCenter()

        try await vm.playAll(artist: artist(withOwnedAlbum: true),
                            client: KimaAPIClient.stubbed(), player: makePlayback(), toast: toast)

        XCTAssertEqual(toast.current?.style, .error)
        XCTAssertEqual(toast.current?.message, "couldn't play abba")
    }

    func testArtistRadioPlaysInTheServersOrderWhenShuffleIsOn() async throws {
        defer { StubURLProtocol.reset() }
        let ids = (1...8).map { "r\($0)" }
        let body = #"{"tracks":["# + ids.map { #"{"id":"\#($0)","title":"t","duration":1}"# }.joined(separator: ",") + "]}"
        StubURLProtocol.handler = { _ in (200, Data(body.utf8)) }
        let player = PlaybackController.stubbed()
        player.play(tracks: try ["x", "y"].map(Track.fixture), shuffle: true)

        await ArtistDetailViewModel().startRadio(artist: try artist(withOwnedAlbum: true),
                                                 client: KimaAPIClient.stubbed(), player: player, toast: ToastCenter())

        XCTAssertEqual(player.playOrder.map { player.queue[$0].id }, ids, "artist radio was reshuffled")
    }
}
