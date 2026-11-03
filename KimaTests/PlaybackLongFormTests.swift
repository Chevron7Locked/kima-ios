import XCTest
@testable import Kima

@MainActor
final class PlaybackLongFormTests: XCTestCase {
    private func makeController() -> PlaybackController {
        PlaybackController(server: KimaServer(baseURL: URL(string: "https://stub.test")!))
    }

    override func tearDown() { StubURLProtocol.reset() }

    func testSaveProgressSkippedWhileLoading() async throws {
        let c = makeController()
        c.playbackType = .audiobook(BookSession(bookId: "b", totalDuration: 200,
            files: [AudiobookTrack(index: 1, startOffset: 0, duration: 100),
                    AudiobookTrack(index: 2, startOffset: 100, duration: 100)]))
        c.currentLongFormFileIndex = 1
        c.longFormAPIClient = .stubbed()
        c.lastSavedProgressTime = 50
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }

        c.engine.status = .loading
        c.saveProgress()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)

        c.engine.status = .paused
        c.engine.currentTime = 60
        c.saveProgress()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testSleepEndOfTrackQueuesNextPaused() throws {
        let c = makeController()
        c.queue = [try Track.fixture("a"), try Track.fixture("b")]
        c.currentIndex = 0
        c.sleepTimer.endPolicy = .endOfTrack
        XCTAssertTrue(c.consumeSleepAfterCurrentItem())
        XCTAssertEqual(c.currentIndex, 1)
        XCTAssertEqual(c.sleepTimer.endPolicy, .timed)
    }

    func testSleepEndOfTrackAtQueueEndRestsAtZero() throws {
        let c = makeController()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        c.sleepTimer.endPolicy = .endOfTrack
        XCTAssertTrue(c.consumeSleepAfterCurrentItem())
        XCTAssertEqual(c.currentIndex, 0)
        XCTAssertEqual(c.displayTime, 0)
    }

    func testRecoveryBudgetIsPerPosition() {
        let c = makeController()
        for _ in 0..<c.maxRecoveryAttempts { XCTAssertTrue(c.consumeRecoveryBudget(at: 10)) }
        XCTAssertFalse(c.consumeRecoveryBudget(at: 10.5))
        XCTAssertTrue(c.consumeRecoveryBudget(at: 40))  // moved position starts a fresh cycle
    }
}
