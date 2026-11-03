import XCTest
@testable import Kima

/// Mirrors the web's station-refill tests: a station refills when its last song starts, adds only new songs,
/// takes a server-ordered batch whole, and ends when a fetch brings nothing new.
@MainActor
final class StationRefillTests: XCTestCase {
    private func tracks(_ ids: [String]) throws -> [Track] { try ids.map { try Track.fixture($0) } }

    func testRefillDropsSongsAlreadyQueued() async throws {
        let queued = try tracks(["a", "b"])
        let session = StationSession(queued: queued, serverOrdered: false) { try self.tracks(["b", "c"]) }
        let fresh = await session.refill(triggerKey: "1:b", queuedNow: { queued })
        XCTAssertEqual(fresh.map(\.id), ["c"])
    }

    func testServerOrderedBatchIsTakenWhole() async throws {
        let queued = try tracks(["a", "b"])
        let session = StationSession(queued: queued, serverOrdered: true) { try self.tracks(["a", "c"]) }
        let fresh = await session.refill(triggerKey: "1:b", queuedNow: { queued })
        XCTAssertEqual(fresh.map(\.id), ["a", "c"])
    }

    func testEndsWhenNothingNewAndTriesOncePerPosition() async throws {
        var calls = 0
        let queued = try tracks(["a"])
        let session = StationSession(queued: queued, serverOrdered: false) {
            calls += 1
            return try self.tracks(["a"])
        }
        _ = await session.refill(triggerKey: "0:a", queuedNow: { queued })
        _ = await session.refill(triggerKey: "0:a", queuedNow: { queued })
        _ = await session.refill(triggerKey: "1:x", queuedNow: { queued })
        XCTAssertEqual(calls, 1, "exhausted after a fetch with nothing new")
    }

    func testFailedFetchRetriesFromTheSamePosition() async throws {
        struct Boom: Error {}
        var fail = true
        let queued = try tracks(["a"])
        let session = StationSession(queued: queued, serverOrdered: false) {
            if fail { fail = false; throw Boom() }
            return try self.tracks(["b"])
        }
        let failed = await session.refill(triggerKey: "0:a", queuedNow: { queued })
        let retried = await session.refill(triggerKey: "0:a", queuedNow: { queued })
        XCTAssertTrue(failed.isEmpty)
        XCTAssertEqual(retried.map(\.id), ["b"])
    }

    func testPlayingTheLastSongAppendsTheNextBatch() async throws {
        let c = PlaybackController.stubbed()
        c.playStation(try tracks(["a"]), serverOrdered: true) { try self.tracks(["b", "c"]) }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(c.queue.map(\.id), ["a", "b", "c"])
    }

    func testANewQueueEndsTheStation() throws {
        let c = PlaybackController.stubbed()
        c.playStation(try tracks(["a", "b"]), serverOrdered: false) { [] }
        c.play(tracks: try tracks(["x"]))
        XCTAssertNil(c.stationSession)
    }

    func testQueueEndingWhileARefillLoadsResumesAtTheFirstNewSong() async throws {
        let c = PlaybackController.stubbed()
        c.playStation(try tracks(["a"]), serverOrdered: false) {
            try await Task.sleep(for: .milliseconds(200))
            return try self.tracks(["b"])
        }
        c.handleEnded()   // the only song ends before its refill lands
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(c.queue.map(\.id), ["a", "b"])
        XCTAssertEqual(c.currentIndex, 1)
    }

    func testAFailedRefillDoesNotStartALaterBatchOnItsOwn() async throws {
        struct Boom: Error {}
        var calls = 0
        let c = PlaybackController.stubbed()
        c.playStation(try tracks(["a"]), serverOrdered: false) {
            calls += 1
            if calls <= 2 { throw Boom() }
            return try self.tracks(["b"])
        }
        try await Task.sleep(for: .milliseconds(100))   // the refill as the only song starts fails
        c.handleEnded()                                   // the queue runs out; that refill fails too
        try await Task.sleep(for: .milliseconds(100))
        c.refillStationIfAtTail()                         // a later refill brings songs
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(c.queue.map(\.id), ["a", "b"])
        XCTAssertEqual(c.currentIndex, 0, "the paused player must not jump to the new song")
    }

    func testATransportTapWhileTheRefillLoadsCancelsTheResume() async throws {
        let c = PlaybackController.stubbed()
        c.playStation(try tracks(["a"]), serverOrdered: false) {
            try await Task.sleep(for: .milliseconds(200))
            return try self.tracks(["b"])
        }
        c.handleEnded()
        c.seek(to: 30)   // the listener scrubs the last song while the refill loads
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(c.queue.map(\.id), ["a", "b"])
        XCTAssertEqual(c.currentIndex, 0)
    }

    func testAServerOrderedStationGivesTheListenersShuffleBack() throws {
        let c = PlaybackController.stubbed()
        c.play(tracks: try tracks(["x", "y"]), shuffle: true)
        c.playStation(try tracks(["a", "b"]), serverOrdered: true) { [] }
        XCTAssertFalse(c.isShuffle)
        XCTAssertTrue(c.queuePlaysInOrder, "the shuffle button shows it is unavailable")
        c.play(tracks: try tracks(["x", "y", "z"]))
        XCTAssertTrue(c.isShuffle, "the station's order must not change the listener's shuffle setting")
        XCTAssertFalse(c.queuePlaysInOrder)
        XCTAssertEqual(c.shuffleOrder.count, 3)
    }

    func testAStationThatRunsDryGivesTheListenersShuffleBack() async throws {
        let c = PlaybackController.stubbed()
        c.play(tracks: try tracks(["x", "y"]), shuffle: true)
        c.playStation(try tracks(["a"]), serverOrdered: true) { [] }   // its first refill brings nothing
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(c.stationSession)
        XCTAssertTrue(c.isShuffle)
        XCTAssertFalse(c.queuePlaysInOrder)
    }

    func testServerOrderedStationRefusesShuffle() throws {
        let c = PlaybackController.stubbed()
        c.playStation(try tracks(["a", "b"]), serverOrdered: true) { [] }
        c.toggleShuffle()
        XCTAssertFalse(c.isShuffle)
    }
}
