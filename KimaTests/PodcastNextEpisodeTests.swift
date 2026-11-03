import XCTest
@testable import Kima

/// At an episode's end the player asks the server what comes next, and falls back to its list only when that fails.
@MainActor
final class PodcastNextEpisodeTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset() }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(400)) }

    /// Playing e2 from a newest-first list [e3, e2, e1]: the list's next row is the OLDER e1.
    private func controller(next: (status: Int, body: String)) throws -> PlaybackController {
        StubURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("/episodes/e2/next") == true { return (next.status, Data(next.body.utf8)) }
            return (200, Data("{}".utf8))
        }
        let c = PlaybackController.stubbed()
        let list = [try Episode.fixture("e3"), try Episode.fixture("e2"), try Episode.fixture("e1")]
        c.playbackType = .podcastEpisode(podcastId: "p", episode: list[1], queue: list)
        c.longFormAPIClient = .stubbed()
        c.engine.status = .paused
        return c
    }

    private func playing(_ c: PlaybackController) -> String? {
        if case .podcastEpisode(_, let episode, _) = c.playbackType { return episode.id }
        return nil
    }

    func testPlaysTheServersNextEpisode() async throws {
        let c = try controller(next: (200, #"""
        {"podcast":{"id":"p","title":"Show","coverUrl":null},
         "episode":{"id":"e3","title":"Three","duration":900,"publishedAt":"2026-01-03T00:00:00Z","coverUrl":null,"progress":null}}
        """#))
        c.handlePodcastEpisodeEnded(autoplay: false)
        try await settle()
        XCTAssertEqual(playing(c), "e3")
    }

    func testStopsAtTheEndOfTheShow() async throws {
        let c = try controller(next: (200, #"{"episode":null}"#))
        c.handlePodcastEpisodeEnded(autoplay: false)
        try await settle()
        XCTAssertEqual(playing(c), "e2")
    }

    func testFallsBackToTheListWhenTheServerFails() async throws {
        let c = try controller(next: (500, "{}"))
        c.handlePodcastEpisodeEnded(autoplay: false)
        try await settle()
        XCTAssertEqual(playing(c), "e1")
    }

    private static let nextIsE3 = #"""
    {"podcast":{"id":"p","title":"Show","coverUrl":null},
     "episode":{"id":"e3","title":"Three","duration":900,"publishedAt":"2026-01-03T00:00:00Z","coverUrl":null,"progress":null}}
    """#

    func testDoesNotWaitForTheFinishedEpisodesSave() async throws {
        let c = try controller(next: (200, Self.nextIsE3))
        c.enqueueProgressSave { try? await Task.sleep(for: .seconds(2)) }   // a save still on its way
        c.handlePodcastEpisodeEnded(autoplay: false)
        try await settle()
        XCTAssertEqual(playing(c), "e3", "the next episode waited on the finished episode's save")
    }

    func testASlowAnswerPlaysTheListsNextRow() async throws {
        let c = try controller(next: (200, Self.nextIsE3))
        StubURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("/episodes/e2/next") == true {
                Thread.sleep(forTimeInterval: 0.6)
                return (200, Data(Self.nextIsE3.utf8))
            }
            return (200, Data("{}".utf8))
        }
        c.podcastNextDeadline = .milliseconds(100)
        c.handlePodcastEpisodeEnded(autoplay: false)
        try await settle()
        XCTAssertEqual(playing(c), "e1", "a slow answer must not hold up the next episode")
        try await Task.sleep(for: .milliseconds(500))   // the slow answer lands
        XCTAssertEqual(playing(c), "e3", "an answer landing just after moves to the server's episode")
    }

    func testAnEarlyAskStillOnItsWayIsNotAskedTwice() async throws {
        let c = try controller(next: (200, Self.nextIsE3))
        StubURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("/episodes/e2/next") == true {
                Thread.sleep(forTimeInterval: 0.6)
                return (200, Data(Self.nextIsE3.utf8))
            }
            return (200, Data("{}".utf8))
        }
        c.podcastNextDeadline = .milliseconds(100)
        _ = c.nextEpisodeLookup(podcastId: "p", episodeId: "e2")
        c.handlePodcastEpisodeEnded(autoplay: false)
        try await Task.sleep(for: .milliseconds(900))
        let asks = StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/next") == true }
        XCTAssertEqual(asks.count, 1, "waited for a second ask after the first was too slow")
        XCTAssertEqual(playing(c), "e3")
    }

    func testTheEndUsesTheAnswerAskedWhenTheEpisodeWasReady() async throws {
        let c = try controller(next: (200, Self.nextIsE3))
        _ = c.nextEpisodeLookup(podcastId: "p", episodeId: "e2")
        try await settle()
        StubURLProtocol.handler = { _ in (500, Data()) }   // offline by the time the episode ends
        c.handlePodcastEpisodeEnded(autoplay: false)
        try await settle()
        XCTAssertEqual(playing(c), "e3")
    }

    func testWarmsTheEpisodeTheServerWillPlayNext() async throws {
        let c = try controller(next: (200, Self.nextIsE3))
        StubURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/auth/stream-ticket") { return (200, Data(#"{"ticket":"t","expiresIn":3600}"#.utf8)) }
            if path.hasSuffix("/episodes/e2/next") { return (200, Data(Self.nextIsE3.utf8)) }
            return (200, Data("{}".utf8))
        }
        c.prefetchNextStream()
        try await settle()
        XCTAssertEqual(c.engine.prefetchedAsset?.url.path, "/api/podcasts/p/episodes/e3/stream",
                       "warmed the list's next row instead of the server's next episode")
    }

    func testASampleSavesNothingAndStopsAtItsEnd() async throws {
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        let c = PlaybackController.stubbed()
        let preview = try JSONDecoder().decode(PodcastPreview.self, from: Data(
            #"{"title":"Show","author":"A","isSubscribed":false}"#.utf8))
        let snippet = PodcastSnippet(title: "First", publishedAt: "2020-01-01T00:00:00Z", duration: 1200)
        c.playPodcastSample(snippet, of: preview, itunesId: "100", client: .stubbed())
        XCTAssertTrue(c.isPlayingSample(of: "100"))
        c.engine.status = .paused
        c.engine.currentTime = 600
        c.saveProgress()
        c.handlePodcastEpisodeEnded(autoplay: false)
        try await settle()
        let paths = StubURLProtocol.requests.compactMap { $0.url?.path }
        XCTAssertFalse(paths.contains { $0.contains("/progress") || $0.hasSuffix("/next") }, "\(paths)")
        XCTAssertEqual(playing(c), "sample-100")
    }
}

