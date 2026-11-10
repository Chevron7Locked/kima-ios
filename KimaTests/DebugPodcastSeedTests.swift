import XCTest
@testable import Kima

/// The `-kima-fake-podcast` fixture must decode into the models the seeded pages use. The app decodes
/// it with `try?`, so a malformed edit (a stray bracket, a renamed field) shows up only as a UI test
/// failing to reach the page — this is where it should fail instead.
final class DebugPodcastSeedTests: XCTestCase {

    func testPodcastFixtureDecodes() throws {
        let podcast = try JSONDecoder().decode(Podcast.self, from: Data(DebugPodcastSeed.podcastJson.utf8))
        XCTAssertEqual(podcast.id, "seed-station")
        XCTAssertEqual(podcast.title, "seed station")
        XCTAssertEqual(podcast.episodeTotal, 5)
        XCTAssertEqual(podcast.episodes.map(\.id), ["seed-1", "seed-2", "seed-3", "seed-4", "seed-5"])
    }

    func testQueueFixtureDecodes() throws {
        let episodes = try JSONDecoder().decode([Episode].self, from: Data(DebugPodcastSeed.queueJson.utf8))
        XCTAssertEqual(episodes.count, 5)
        XCTAssertEqual(episodes.first?.title, "seed one")
    }

    /// Seed one carries progress so the detail page's "continue listening" section renders — the
    /// UI tests' gate for "the seeded page appeared".
    func testSeedOneCarriesProgress() throws {
        let episodes = try JSONDecoder().decode([Episode].self, from: Data(DebugPodcastSeed.queueJson.utf8))
        let progress = try XCTUnwrap(episodes.first?.progress)
        XCTAssertEqual(progress.currentTime, 260)
        XCTAssertFalse(progress.isFinished)
    }
}
