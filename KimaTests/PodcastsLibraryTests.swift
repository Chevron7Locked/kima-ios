import XCTest
@testable import Kima

/// The podcasts page's sort and its "because you follow" line.
final class PodcastsLibraryTests: XCTestCase {
    private func show(_ id: String, latest: String?) throws -> Podcast {
        let latestJSON = latest.map { "\"\($0)\"" } ?? "null"
        return try JSONDecoder().decode(Podcast.self, from: Data(
            #"{"id":"\#(id)","title":"\#(id)","author":"a","autoDownloadEpisodes":false,"episodes":[],"latestEpisodeAt":\#(latestJSON)}"#.utf8))
    }

    func testLatestEpisodeSortPutsNewestFirstAndEmptyLast() throws {
        let shows = [try show("old", latest: "2026-01-01T00:00:00.000Z"),
                     try show("none", latest: nil),
                     try show("new", latest: "2026-10-01T00:00:00.000Z")]
        XCTAssertEqual(PodcastLibrarySortOption.latestEpisode.sort(shows).map(\.id), ["new", "old", "none"])
    }

    func testBecauseLine() {
        XCTAssertNil(PodcastDiscoverySections.becauseLine([]))
        XCTAssertEqual(PodcastDiscoverySections.becauseLine(["A"]), "because you follow a")
        XCTAssertEqual(PodcastDiscoverySections.becauseLine(["A", "B"]), "because you follow a and b")
        XCTAssertEqual(PodcastDiscoverySections.becauseLine(["A", "B", "C", "D"]), "because you follow a, b and 2 more")
    }
}
