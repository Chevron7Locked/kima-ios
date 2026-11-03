import XCTest
@testable import Kima

/// Server shapes for podcast discovery: categories, charts, for-you, listening, next episode, preview.
final class PodcastDiscoveryDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private let item = #"""
    {"id":"100","itunesId":"100","title":"Show","author":"A","description":"About","coverUrl":null,"feedUrl":null,
     "genres":["Improv"],"categoryIds":[1495],"episodeCount":0,"chartRank":1,"isExternal":true}
    """#

    func testCategoryTree() throws {
        let tree = try decode([PodcastCategory].self,
            #"[{"id":1303,"name":"Comedy","parentId":null},{"id":1486,"name":"Comedy Fiction","parentId":1483}]"#)
        XCTAssertNil(tree[0].parentId)
        XCTAssertEqual(tree[1], PodcastCategory(id: 1486, name: "Comedy Fiction", parentId: 1483))
    }

    func testChartItemCarriesRankAndCategories() throws {
        let show = try decode(DiscoveryPodcast.self, item)
        XCTAssertEqual(show.chartRank, 1)
        XCTAssertEqual(show.categoryIds, [1495])
        XCTAssertEqual(show.description, "About")
        XCTAssertEqual(show.itunesId, "100")
    }

    func testForYouRow() throws {
        let rows = try decode([PodcastForYouRow].self,
            #"[{"category":{"id":1495,"name":"Improv","parentId":1303},"because":["Mine"],"podcasts":[\#(item)]}]"#)
        XCTAssertEqual(rows[0].id, 1495)
        XCTAssertEqual(rows[0].because, ["Mine"])
        XCTAssertEqual(rows[0].podcasts.map(\.id), ["100"])
    }

    func testListeningRows() throws {
        let listening = try decode(PodcastListening.self, #"""
        {"inProgress":[{"podcast":{"id":"p1","title":"Show","coverUrl":null},
          "episode":{"id":"e1","title":"Ep","description":"d","duration":1800,"publishedAt":"2026-10-01T00:00:00.000Z",
           "coverUrl":"https://x/y.jpg","progress":{"currentTime":60,"progress":3.3,"isFinished":false,"lastPlayedAt":"2026-10-02T00:00:00.000Z"}}}],
         "newEpisodes":[{"podcast":{"id":"p2","title":"Other","coverUrl":"/c"},
          "episode":{"id":"e2","title":"New","description":null,"duration":600,"publishedAt":"2026-10-03T00:00:00.000Z","coverUrl":null,"progress":null}}]}
        """#)
        XCTAssertEqual(listening.inProgress[0].podcast.id, "p1")
        XCTAssertEqual(listening.inProgress[0].episode.progress?.currentTime, 60)
        let episode = listening.newEpisodes[0].episode.asEpisode
        XCTAssertEqual(episode.id, "e2")
        XCTAssertNil(episode.progress)
        XCTAssertEqual(episode.duration, 600)
    }

    func testNextEpisodeAndEndOfShow() throws {
        let next = try decode(PodcastNextEpisode.self, #"""
        {"podcast":{"id":"p1","title":"Show","coverUrl":null},
         "episode":{"id":"e2","title":"Two","duration":900,"publishedAt":"2026-10-03T00:00:00.000Z","coverUrl":null,"progress":null}}
        """#)
        XCTAssertEqual(next.episode?.id, "e2")
        XCTAssertNil(next.episode?.description)
        XCTAssertNil(try decode(PodcastNextEpisode.self, #"{"episode":null}"#).episode)
    }

    func testPreviewCarriesCategoriesSnippetAndSummaries() throws {
        let preview = try decode(PodcastPreview.self, #"""
        {"itunesId":"100","title":"Show","author":"A","description":"","coverUrl":null,"feedUrl":"https://f",
         "genres":["Improv"],"categories":[{"id":1495,"name":"Improv"}],"episodeCount":12,
         "previewEpisodes":[{"title":"Ep","publishedAt":"2026-10-01T00:00:00.000Z","duration":60,"description":"Sum"}],
         "snippet":{"title":"First","publishedAt":"2020-01-01T00:00:00.000Z","duration":1200,"description":"x"},
         "isSubscribed":false,"subscribedPodcastId":null}
        """#)
        XCTAssertEqual(preview.categories, [PodcastCategoryRef(id: 1495, name: "Improv")])
        XCTAssertEqual(preview.snippet?.title, "First")
        XCTAssertEqual(preview.previewEpisodes?.first?.description, "Sum")
    }

    func testPodcastListCarriesLatestEpisodeAt() throws {
        let shows = try decode([Podcast].self, #"""
        [{"id":"p1","title":"S","author":"A","description":null,"coverUrl":null,"episodeCount":3,
          "autoDownloadEpisodes":false,"latestEpisodeAt":"2026-10-03T00:00:00.000Z","episodes":[]}]
        """#)
        XCTAssertEqual(shows[0].latestEpisodeAt, "2026-10-03T00:00:00.000Z")
        XCTAssertNil(shows[0].categories)
    }
}
