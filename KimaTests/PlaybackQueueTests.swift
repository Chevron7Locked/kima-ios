import XCTest
@testable import Kima

@MainActor
final class PlaybackQueueTests: XCTestCase {

    override func tearDown() { StubURLProtocol.reset() }

    private func controller() -> PlaybackController {
        PlaybackController(server: KimaServer(baseURL: URL(string: "http://test.local")!))
    }

    func testFullStopOnSingleTrackKeepsQueue() throws {
        let c = controller()
        c.queue = [try Track.fixture("a")]
        c.applyMusicFailurePolicy()
        XCTAssertEqual(c.queue.map(\.id), ["a"])
        XCTAssertEqual(c.engine.status, .error)
        XCTAssertNotNil(c.engine.audioError)
    }

    func testThirdFailureKeepsQueueAndPlace() throws {
        let c = controller()
        c.queue = [try Track.fixture("a"), try Track.fixture("b"), try Track.fixture("c")]
        c.currentIndex = 1
        c.consecutiveErrorCount = 2
        c.applyMusicFailurePolicy()
        XCTAssertEqual(c.consecutiveErrorCount, 3)
        XCTAssertEqual(c.currentIndex, 1)
        XCTAssertEqual(c.queue.count, 3)
        XCTAssertEqual(c.engine.status, .error)
    }

    func testEnqueueUnderShuffleExtendsPlayOrder() throws {
        let c = controller()
        c.queue = [try Track.fixture("a"), try Track.fixture("b"), try Track.fixture("c")]
        c.isShuffle = true
        c.shuffleOrder = [1, 0, 2]
        c.currentIndex = 1
        c.enqueue(tracks: [try Track.fixture("d"), try Track.fixture("e")])
        XCTAssertEqual(c.shuffleOrder, [1, 0, 2, 3, 4])
        XCTAssertEqual(c.queue.count, 5)
    }

    func testPausedSeekUpdatesTimes() throws {
        let c = controller()
        c.queue = [try Track.fixture("a")]
        c.seek(to: 42)
        XCTAssertEqual(c.displayTime, 42)
        XCTAssertEqual(c.engine.currentTime, 42)
        XCTAssertEqual(c.lastKnownMusicPosition, 42)
    }

    func testLoadKeepsSessionMode() {
        let c = controller()
        c.engine.claimAudioSession(mode: .spokenAudio)
        c.engine.claimAudioSession()
        XCTAssertEqual(c.engine.sessionMode, .spokenAudio)
    }

    func testPlayClearsVibeSession() throws {
        let c = controller()
        c.playVibeQueue([try Track.fixture("a")], origin: .playSimilar, similarities: ["a": 1])
        XCTAssertTrue(c.isVibeQueue)
        c.play(tracks: [try Track.fixture("b")])
        XCTAssertFalse(c.isVibeQueue)
        XCTAssertNil(c.queueOrigin)
        XCTAssertTrue(c.vibeSimilarities.isEmpty)
    }

    func testEveryVibeQueueTurnsTheButtonOnButOnlyPlaySimilarShowsAScore() throws {
        let c = controller()
        for origin in [QueueOrigin.songPath, .blend] {
            c.playVibeQueue([try Track.fixture("a"), try Track.fixture("b")], origin: origin, similarities: ["a": 0.9])
            XCTAssertTrue(c.isVibeQueue, origin.name)
            XCTAssertNil(c.vibeMatchScore, origin.name)
        }
        c.playVibeQueue([try Track.fixture("a"), try Track.fixture("b")], origin: .playSimilar, similarities: ["a": 1, "b": 0.42])
        XCTAssertEqual(c.vibeMatchScore, 100)
        XCTAssertFalse(c.isShuffle)
    }

    func testShuffleIgnoredDuringVibeQueue() throws {
        let c = controller()
        c.play(tracks: [try Track.fixture("a"), try Track.fixture("b")])
        c.queueOrigin = .songPath
        c.toggleShuffle()
        XCTAssertFalse(c.isShuffle)
        c.queueOrigin = nil
        c.toggleShuffle()
        XCTAssertTrue(c.isShuffle)
    }

    func testReplaceGateAsksOnlyDuringVibeQueue() async {
        let c = controller()
        let free = await c.confirmVibeReplace(with: .blend)
        XCTAssertTrue(free)
        c.queueOrigin = .songPath
        let answer = Task { await c.confirmVibeReplace(with: .playSimilar) }
        while c.vibeReplacePrompt == nil { await Task.yield() }
        XCTAssertEqual(c.vibeReplacePrompt?.question, "replace the song path with similar tracks?")
        c.resolveVibeReplace(true)
        let confirmed = await answer.value
        XCTAssertTrue(confirmed)
        XCTAssertNil(c.vibeReplacePrompt)
    }

    private var book: LongFormPlaybackType {
        .audiobook(BookSession(bookId: "b", totalDuration: 10, files: [AudiobookTrack(index: 1, startOffset: 0, duration: 10)]))
    }

    private func podcast() throws -> LongFormPlaybackType {
        let ep = try JSONDecoder().decode(Episode.self, from: Data(
            #"{"id":"e","title":"e","duration":10,"publishedAt":"2026-01-01T00:00:00Z"}"#.utf8))
        return .podcastEpisode(podcastId: "p", episode: ep, queue: [ep])
    }

    func testPlayNextDuringLongFormSaysWhatStopped() throws {
        let c = controller()
        c.playbackType = book
        XCTAssertEqual(c.playNext(try Track.fixture("a")), .stoppedAudiobook)
        c.playbackType = try podcast()
        XCTAssertEqual(c.playNext(try Track.fixture("a")), .stoppedPodcast)
    }

    func testAddToQueueDuringAnAudiobookReplacesItAndSaysSo() throws {
        let c = controller()
        c.playbackType = book
        XCTAssertEqual(c.enqueue(track: try Track.fixture("a")), .stoppedAudiobook)
        XCTAssertEqual(c.queue.map(\.id), ["a"])
        XCTAssertFalse(c.playbackType.isLongForm)
    }

    func testAddToQueueDuringAPodcastReplacesItAndSaysSo() throws {
        let c = controller()
        c.playbackType = try podcast()
        XCTAssertEqual(c.enqueue(tracks: [try Track.fixture("a"), try Track.fixture("b")]), .stoppedPodcast)
        XCTAssertEqual(c.queue.map(\.id), ["a", "b"])
    }

    func testAddToQueueWhenIdleStartsAndWithAQueueAppends() throws {
        let c = controller()
        XCTAssertEqual(c.enqueue(track: try Track.fixture("a")), .startedIdle)
        XCTAssertEqual(c.enqueue(track: try Track.fixture("b")), .added)
        XCTAssertEqual(c.queue.map(\.id), ["a", "b"])
        XCTAssertEqual(c.currentIndex, 0, "adding never moves the current track")
    }

    func testRestoredTrackShowsItsOwnLengthAndCanBeSeekedBeforePlay() throws {
        let c = controller()
        c.hydrateFromServer(queue: [try Track.fixture("a")], currentIndex: 0, isShuffle: false)
        XCTAssertEqual(c.engineStatus, .idle)
        XCTAssertEqual(c.duration, 100, "the track's own length until the stream loads")
        XCTAssertTrue(c.canSeek)
        c.seek(to: 30)
        XCTAssertEqual(c.lastKnownMusicPosition, 30, "play starts here")
        c.engine.duration = 98.5
        XCTAssertEqual(c.duration, 98.5, "the loaded stream's length wins")
    }

    func testNothingLoadedHasNoLengthAndNoSeek() {
        let c = controller()
        XCTAssertEqual(c.duration, 0)
        XCTAssertFalse(c.canSeek)
    }

    // MARK: Wrapping at the end of the queue

    func testAutoAdvanceWrapsAtTheEndOnlyWithRepeatAll() throws {
        let c = controller()
        c.queue = [try Track.fixture("a"), try Track.fixture("b")]
        c.currentIndex = 1
        for (mode, wraps) in [(RepeatMode.off, false), (.one, false), (.all, true)] {
            c.repeatMode = mode
            XCTAssertEqual(c.computeNext().queueIndex, wraps ? 0 : nil, "repeat \(mode)")
        }
    }

    // MARK: - Transport button capabilities at the queue ends

    func testNextGreyedOnLastTrackOnlyWithoutRepeat() throws {
        let c = controller()
        c.queue = [try Track.fixture("a"), try Track.fixture("b")]
        c.currentIndex = 1
        XCTAssertFalse(c.canGoNext, "last track, repeat off: next has nowhere to go")
        c.repeatMode = .all
        XCTAssertTrue(c.canGoNext, "repeat-all wraps to the first track")
        c.repeatMode = .one
        XCTAssertTrue(c.canGoNext, "repeat-one's first Next restarts the current track")
        c.repeatOneRestartConsumed = true
        XCTAssertTrue(c.canGoNext, "after the restart, repeat-one behaves like repeat-all")
    }

    func testPreviousGreyedOnFirstTrackAtTheTop() throws {
        let c = controller()
        c.queue = [try Track.fixture("a"), try Track.fixture("b")]
        XCTAssertFalse(c.canGoPrevious, "first track at the top: previous has nowhere to go")
        c.engine.currentTime = 3.5
        XCTAssertTrue(c.canGoPrevious, "3 s in, previous means restart this track")
        c.engine.currentTime = 0
        c.repeatMode = .all
        XCTAssertTrue(c.canGoPrevious, "repeat-all wraps to the last track")
    }

    func testTransportCapabilitiesFollowPlayOrderUnderShuffle() throws {
        let c = controller()
        c.queue = [try Track.fixture("a"), try Track.fixture("b"), try Track.fixture("c")]
        c.isShuffle = true
        c.shuffleOrder = [1, 0, 2]
        c.shufflePosition = 0
        XCTAssertTrue(c.canGoNext)
        XCTAssertFalse(c.canGoPrevious, "first in shuffle order, nothing before it")
        c.shufflePosition = 2
        XCTAssertFalse(c.canGoNext, "last in shuffle order, nothing after it")
        XCTAssertTrue(c.canGoPrevious)
    }

    func testTransportButtonsGreyedWithNothingLoaded() {
        let c = controller()
        XCTAssertFalse(c.canGoNext)
        XCTAssertFalse(c.canGoPrevious)
    }

    func testManualNextWrapsAtTheEndWithRepeatAllAndRepeatOneButNotOff() throws {
        StubURLProtocol.handler = { _ in (404, Data()) }
        for (mode, expected) in [(RepeatMode.off, 1), (.one, 0), (.all, 0)] {
            let c = PlaybackController.stubbed()
            c.apiClient = .stubbed()
            c.queue = [try Track.fixture("a"), try Track.fixture("b")]
            c.currentIndex = 1
            c.repeatMode = mode
            c.repeatOneRestartConsumed = true   // the first Next under repeat one only restarts
            c.next()
            XCTAssertEqual(c.currentIndex, expected, "repeat \(mode)")
        }
    }
}
