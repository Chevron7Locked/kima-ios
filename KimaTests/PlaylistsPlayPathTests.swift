import XCTest
@testable import Kima

/// The playlist grid's play path (`PlaylistsListViewModel.play`): it shows a busy state, and says so
/// when the playlist has no items, so a tap on an empty playlist never looks like a tap that worked.
@MainActor
final class PlaylistsPlayPathTests: XCTestCase {

    private func client() -> KimaAPIClient { KimaAPIClient.stubbed() }

    private func makePlayback() -> PlaybackController {
        PlaybackController(server: KimaServer(baseURL: URL(string: "https://stub.test")!))
    }

    private static let playlistWithItems = """
    {"id":"p1","name":"Night Drive","isPublic":false,"trackCount":2,"items":[
      {"id":"i1","sort":0,"track":{"id":"t1","title":"Move","duration":220,
        "album":{"id":"a1","title":"Exercise","artist":{"id":"ar1","name":"Cyhi the Prairie"}}}},
      {"id":"i2","sort":1,"track":{"id":"t2","title":"Say So","duration":180,
        "album":{"id":"a1","title":"Exercise","artist":{"id":"ar1","name":"Cyhi the Prairie"}}}}]}
    """

    private static let emptyPlaylist = """
    {"id":"p2","name":"Nothing Here","isPublic":false,"trackCount":0,"items":[]}
    """

    private static func summary(id: String, name: String, count: Int) -> PlaylistSummary {
        PlaylistSummary(id: id, name: name, isPublic: false, isOwner: true, isHidden: false,
                        user: nil, trackCount: count, items: nil)
    }

    /// The card is marked busy while the detail request runs, then clears when playback starts.
    func testPlayMarksThatPlaylistCardBusyWhileTheFetchRuns() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in
            Thread.sleep(forTimeInterval: 0.35)
            return (200, Data(Self.playlistWithItems.utf8))
        }
        let vm = PlaylistsListViewModel()
        let player = makePlayback()
        let toast = ToastCenter()

        let task = Task {
            await vm.play(playlist: Self.summary(id: "p1", name: "Night Drive", count: 2),
                          using: client(), player: player, toast: toast)
        }
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(vm.startingIds.contains("p1"), "the playlist card was not marked busy during the fetch")
        await task.value
        XCTAssertTrue(vm.startingIds.isEmpty, "the card stayed busy after playback started")
        XCTAssertEqual(player.queue.map(\.id), ["t1", "t2"], "playlist order is not what reached the queue")
    }

    /// A tap on an empty playlist says so and leaves the queue alone.
    func testEmptyPlaylistSaysSoInsteadOfPlayingNothing() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (200, Data(Self.emptyPlaylist.utf8)) }
        let vm = PlaylistsListViewModel()
        let player = makePlayback()
        let toast = ToastCenter()

        await vm.play(playlist: Self.summary(id: "p2", name: "Nothing Here", count: 0),
                      using: client(), player: player, toast: toast)

        XCTAssertTrue(player.queue.isEmpty, "an empty playlist changed the queue")
        XCTAssertTrue(toast.current?.message.localizedCaseInsensitiveContains("empty") == true,
                      "nothing told the user the playlist is empty (\(toast.current?.message ?? "no toast"))")
    }

    /// A repeat tap while the detail is loading must not start a second play.
    func testRepeatTapOnOnePlaylistIsIgnoredWhileItsFetchRuns() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in
            Thread.sleep(forTimeInterval: 0.35)
            return (200, Data(Self.playlistWithItems.utf8))
        }
        let vm = PlaylistsListViewModel()
        let player = makePlayback()
        let toast = ToastCenter()
        let playlist = Self.summary(id: "p1", name: "Night Drive", count: 2)

        let first = Task { await vm.play(playlist: playlist, using: client(), player: player, toast: toast) }
        try await Task.sleep(for: .milliseconds(120))
        await vm.play(playlist: playlist, using: client(), player: player, toast: toast)
        await first.value

        XCTAssertEqual(StubURLProtocol.requests.count, 1, "the repeat tap started a second play")
    }
}
