import XCTest
@testable import Kima

@MainActor
final class CollectionViewModelTests: XCTestCase {

    private func client() -> KimaAPIClient {
        KimaAPIClient(server: KimaServer(baseURL: URL(string: "http://127.0.0.1:9")!), credential: nil)
    }

    func testSelectTabResetsSortUnavailableOnNewTab() {
        let vm = CollectionViewModel()
        vm.sortBy = .tracks   // artists-only
        vm.selectTab(.albums, using: client())
        XCTAssertEqual(vm.sortBy, .name)
    }

    func testSelectTabKeepsSortAvailableOnNewTab() {
        let vm = CollectionViewModel()
        vm.sortBy = .nameDesc
        vm.selectTab(.tracks, using: client())
        XCTAssertEqual(vm.sortBy, .nameDesc)
    }

    func testChangedFilterShowsLoadingNotTheOldResults() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in
            Thread.sleep(forTimeInterval: 0.3)
            return (200, Data(#"{"albums":[{"id":"a1","title":"t"}],"total":1}"#.utf8))
        }
        let vm = CollectionViewModel()
        vm.activeTab = .albums
        let client = KimaAPIClient.stubbed()
        await vm.loadAlbums(using: client)
        XCTAssertTrue(vm.albumsPhase.isLoaded)

        // Same filter and sort: the loaded grid stays up while the refresh runs.
        let refresh = Task { await vm.loadAlbums(using: client) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(vm.albumsPhase.isLoaded)
        await refresh.value

        // Another filter: the old grid is replaced by the loading state.
        vm.filter = .all
        let refilter = Task { await vm.loadAlbums(using: client) }
        try await Task.sleep(for: .milliseconds(100))
        guard case .loading = vm.albumsPhase else { return XCTFail("old results still shown") }
        await refilter.value
        XCTAssertTrue(vm.albumsPhase.isLoaded)
    }

    func testPhoneArtistOrderIgnoresLeadingThe() throws {
        let artists = try ["The Beatles", "Abba", "Cream"].enumerated().map { i, name in
            try JSONDecoder().decode(Artist.self, from: Data(#"{"id":"\#(i)","name":"\#(name)"}"#.utf8))
        }
        XCTAssertEqual(CollectionViewModel.sortedByName(artists).map(\.name), ["Abba", "The Beatles", "Cream"])
    }

    // MARK: - Playing from a card (badge busy state, tap guard, failure toast)

    private func makePlayback() -> PlaybackController {
        PlaybackController(server: KimaServer(baseURL: URL(string: "https://stub.test")!))
    }

    /// What the play-tracks route answers for one artist: the play queue, in the order the server
    /// owns (newest album first, disc then track inside it), with no audio features, no discography
    /// and no album fields the player does not read.
    ///
    /// Every row here is a track the library has as a file. That is the endpoint's contract — the
    /// `dz:` preview rows in the artist page's popularity list never appear in this response, which
    /// is why the client no longer filters anything: it queues the rows it is given.
    private static let playTracksPayload = """
    {"artist":{"id":"art1","name":"ABBA"},"tracks":[
      {"id":"t1","title":"When I Passed the Door","duration":230,"trackNo":1,"discNumber":1,
       "album":{"id":"alb1","title":"Arrival","coverArt":"/cover/1"},"artist":{"id":"art1","name":"ABBA"}},
      {"id":"t2","title":"Dancing Queen","duration":250,"trackNo":2,"discNumber":1,
       "album":{"id":"alb1","title":"Arrival","coverArt":"/cover/1"},"artist":{"id":"art1","name":"ABBA"}},
      {"id":"t0","title":"Waterloo","duration":150,"trackNo":1,"discNumber":1,
       "album":{"id":"alb0","title":"Waterloo","coverArt":"/cover/0"},"artist":{"id":"art1","name":"ABBA"}}]}
    """

    private static let albumPage = """
    {"id":"alb2","title":"Greatest Hits","year":1992,"owned":true,
     "tracks":[{"id":"t20","title":"The Winner Takes It All","duration":290,"trackNo":1}]}
    """

    /// Answers slowly, so a test can look at the middle of a play.
    private static let slowPlayTracksHandler: (URLRequest) -> (status: Int, body: Data) = { _ in
        Thread.sleep(forTimeInterval: 0.4)
        return (200, Data(playTracksPayload.utf8))
    }

    func testCardPlayMarksThatCardBusyWhileTheFetchRuns() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = Self.slowPlayTracksHandler
        let vm = CollectionViewModel()
        let toast = ToastCenter()
        let run = Task {
            await vm.playArtist(id: "art1", using: KimaAPIClient.stubbed(), player: makePlayback(), toast: toast)
        }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(vm.startingIds.contains("art1"), "the tapped card is not marked busy while its tracks are fetched")
        XCTAssertTrue(vm.startingIds.contains("art1"), "the play is not tracked as in flight")
        await run.value
        XCTAssertTrue(vm.startingIds.isEmpty, "the busy flag is still set after the play finished")
        XCTAssertTrue(vm.startingIds.isEmpty, "the play is still tracked as in flight after it finished")
    }

    /// A repeat tap on the card that is already loading must not start a second play.
    func testRepeatCardPlayTapIsIgnoredWhileOneIsInFlight() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = Self.slowPlayTracksHandler
        let vm = CollectionViewModel()
        let client = KimaAPIClient.stubbed()
        let player = makePlayback()
        let toast = ToastCenter()

        let first = Task { await vm.playArtist(id: "art1", using: client, player: player, toast: toast) }
        try await Task.sleep(for: .milliseconds(120))
        await vm.playArtist(id: "art1", using: client, player: player, toast: toast)   // the same card, smashed
        await first.value

        XCTAssertEqual(StubURLProtocol.requests.count, 1, "a repeat tap started a second play")
        XCTAssertTrue(vm.startingIds.isEmpty)
    }

    /// Tapping a *different* card while one is loading starts that one too. The old single-slot
    /// lock returned here with no spinner and no toast — the reported "I sat there smashing
    /// artists and nothing happened" experience.
    func testTappingAnotherCardWhileOneIsInFlightStartsIt() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { req in
            Thread.sleep(forTimeInterval: 0.4)
            if req.url?.path.contains("/albums/") == true { return (200, Data(Self.albumPage.utf8)) }
            return (200, Data(Self.playTracksPayload.utf8))
        }
        let vm = CollectionViewModel()
        let client = KimaAPIClient.stubbed()
        let player = makePlayback()
        let toast = ToastCenter()

        let first = Task { await vm.playArtist(id: "art1", using: client, player: player, toast: toast) }
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(vm.startingIds.contains("art1"), "the first card lost its busy marker while its fetch was running")
        await vm.playAlbum(id: "alb2", using: client, player: player, toast: toast)

        XCTAssertEqual(player.queue.map(\.id), ["t20"], "the second card's music never reached the queue")
        await first.value
        XCTAssertTrue(vm.startingIds.isEmpty, "a card stayed busy after its playback started")
    }

    /// Card play queues exactly the rows the play-tracks endpoint returned, in the order it
    /// returned them: newest album first (Arrival 1976 before Waterloo 1974), disc and track number
    /// inside the album. The client adds nothing, drops nothing, and does not re-sort by track
    /// number — the server owns that order.
    func testCardPlayQueuesTheArtistsOwnTracksInServerOrder() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (200, Data(Self.playTracksPayload.utf8)) }
        let vm = CollectionViewModel()
        let player = makePlayback()
        let toast = ToastCenter()

        await vm.playArtist(id: "art1", using: KimaAPIClient.stubbed(), player: player, toast: toast)

        XCTAssertEqual(player.queue.map(\.id), ["t1", "t2", "t0"],
                       "the queue is not the artist's own tracks in newest-album, disc, track order")
        XCTAssertEqual(player.queue.count, 3, "the client added or dropped rows from the server's queue")
        XCTAssertNil(toast.current)
    }

    /// Playing from a card fetches the artist's play queue, not the artist page. The page answers
    /// the same tap with the full discography, per-track audio features and a MusicBrainz block:
    /// measured on the live server at 1,012,720 bytes and 180 ms to start one track for an artist
    /// with 101 albums.
    func testCardPlayRequestsThePlayQueueNotTheArtistPage() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (200, Data(Self.playTracksPayload.utf8)) }
        let vm = CollectionViewModel()

        await vm.playArtist(id: "art1", using: KimaAPIClient.stubbed(),
                            player: makePlayback(), toast: ToastCenter())

        XCTAssertEqual(StubURLProtocol.requests.count, 1, "card play made more than one request")
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/api/library/artists/art1/play-tracks",
                       "card play did not use the lean play-tracks endpoint")
    }

    func testCardPlayFailureIsReportedNotSwallowed() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (500, Data(#"{"error":"boom"}"#.utf8)) }
        let vm = CollectionViewModel()
        let toast = ToastCenter()

        await vm.playArtist(id: "art1", using: KimaAPIClient.stubbed(), player: makePlayback(), toast: toast)

        XCTAssertEqual(toast.current?.style, .error)
        XCTAssertEqual(toast.current?.message, "couldn't play that artist")
        XCTAssertTrue(vm.startingIds.isEmpty)
    }
}
