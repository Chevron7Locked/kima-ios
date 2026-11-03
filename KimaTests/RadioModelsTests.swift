import XCTest
@testable import Kima

final class RadioModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testMoodStationInfoDecodes() throws {
        let station = try decode(
            MoodStationInfo.self,
            #"{"value":"focus-calm","name":"Focus: Calm","description":"Steady, low-key songs"}"#
        )
        XCTAssertEqual(station, MoodStationInfo(value: "focus-calm", name: "Focus: Calm", description: "Steady, low-key songs"))
    }

    func testRadioPageWithNext() throws {
        let page = try decode(RadioPage.self, #"{"tracks":[{"id":"t1","title":"a","duration":120}],"next":100}"#)
        XCTAssertEqual(page.tracks.map(\.id), ["t1"])
        XCTAssertEqual(page.next, 100)
    }

    func testRadioPageWithoutNext() throws {
        let page = try decode(RadioPage.self, #"{"tracks":[],"message":"retired"}"#)
        XCTAssertTrue(page.tracks.isEmpty)
        XCTAssertNil(page.next)
    }

    func testSeedMatchesServerPattern() {
        let seed = RadioPage.newSeed()
        XCTAssertNotNil(seed.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression))
        XCTAssertNotEqual(seed, RadioPage.newSeed())
    }

    func testMoodStationsKeepServerOrderAndNeedMoods() {
        let stations = RadioStationData.buildMoodStations(from: [
            MoodStationInfo(value: "calm", name: "Calm", description: "d"),
            MoodStationInfo(value: "brand-new", name: "New", description: "d"),
        ])
        XCTAssertEqual(stations.map(\.id), ["mood-calm", "mood-brand-new"])
        XCTAssertEqual(stations.map(\.filterType), ["mood", "mood"])
        XCTAssertEqual(stations.map(\.filterValue), ["calm", "brand-new"])
        XCTAssertTrue(stations.allSatisfy { $0.needsMoods && $0.minTracks == 1 })
    }

    func testPlayableDropsMoodStationsWithoutEmbeddings() {
        let all = RadioStationData.staticStations
            + RadioStationData.buildMoodStations(from: [MoodStationInfo(value: "calm", name: "Calm", description: "d")])
        let ids = RadioStationData.playable(all, moodsAvailable: false).map(\.id)
        XCTAssertEqual(ids, ["all", "discovery", "favorites"])
        XCTAssertEqual(RadioStationData.playable(all, moodsAvailable: true).count, all.count)
    }

    func testStationIconsSayWhatTheStationIs() {
        let quick = RadioStationData.staticStations.map(\.symbol)
        XCTAssertEqual(quick, ["shuffle", "figure.run", "safari", "heart"])
        XCTAssertEqual(RadioStationData.buildGenreStations(from: [RadioGenre(genre: "rock", count: 20)]).first?.symbol, "guitars")
        XCTAssertEqual(RadioStationData.buildDecadeStations(from: [RadioDecade(decade: 1990, count: 20)]).first?.symbol, "calendar")
    }
}
