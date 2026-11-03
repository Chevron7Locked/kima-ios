import XCTest
@testable import Kima

/// Small rules behind the lyrics panel, the sleep timer sheet and Home's continue listening.
@MainActor
final class PlayerSheetLogicTests: XCTestCase {
    private let lines = [LyricLine(timeMs: 12_000, text: "first"), LyricLine(timeMs: 20_000, text: "second")]

    func testNoLyricLineIsLitDuringTheIntro() {
        XCTAssertNil(activeLyricIndex(at: 0, in: lines))
        XCTAssertNil(activeLyricIndex(at: 11_999, in: lines))
        XCTAssertEqual(activeLyricIndex(at: 12_000, in: lines), 0)
        XCTAssertEqual(activeLyricIndex(at: 25_000, in: lines), 1)
        XCTAssertNil(activeLyricIndex(at: 5_000, in: []))
    }

    func testSleepTimerOffersTheEndOfWhatIsPlaying() throws {
        XCTAssertEqual(SleepTimerEndPolicy.endOfItem(for: .track), .endOfTrack)
        let episode = try Episode.fixture("e1")
        XCTAssertEqual(SleepTimerEndPolicy.endOfItem(for: .podcastEpisode(podcastId: "p", episode: episode, queue: [episode])),
                       .endOfEpisode)
    }

    func testPlayerTellsTheSleepTimerWhatIsPlaying() {
        let player = PlaybackController.stubbed()
        XCTAssertEqual(player.sleepTimer.currentPlayback?().isLongForm, false)
    }

    func testResumeEpisodePrefersOneInProgress() throws {
        let json = #"[{"id":"new","title":"n","duration":60,"publishedAt":"2026-01-03T00:00:00Z"},{"id":"started","title":"s","duration":60,"publishedAt":"2026-01-02T00:00:00Z","progress":{"currentTime":30,"progress":50,"isFinished":false,"lastPlayedAt":"2026-01-04T00:00:00Z"}}]"#
        let episodes = try JSONDecoder().decode([Episode].self, from: Data(json.utf8))
        XCTAssertEqual(PlaybackController.resumeEpisode(in: episodes)?.id, "started")
        XCTAssertEqual(PlaybackController.resumeEpisode(in: [episodes[0]])?.id, "new")
        XCTAssertNil(PlaybackController.resumeEpisode(in: []))
    }

    func testContinueCardSaysWhatTheItemIs() throws {
        func item(_ type: String?) throws -> RecentlyListenedItem {
            let t = type.map { #","type":"\#($0)""# } ?? ""
            return try JSONDecoder().decode(RecentlyListenedItem.self, from: Data(#"{"id":"x"\#(t)}"#.utf8))
        }
        XCTAssertEqual(try item("Album").typeLabel, "album")
        XCTAssertEqual(try item("audiobook").typeLabel, "audiobook")
        XCTAssertEqual(try item(nil).typeLabel, "artist")
    }

    func testToastActionRunsOnceAndClosesTheToast() {
        let center = ToastCenter()
        var runs = 0
        center.show("hidden", action: ToastAction(label: "undo") { runs += 1 })
        XCTAssertEqual(center.current?.action?.label, "undo")
        center.performAction()
        center.performAction()
        XCTAssertEqual(runs, 1)
        XCTAssertNil(center.current)
    }
}
