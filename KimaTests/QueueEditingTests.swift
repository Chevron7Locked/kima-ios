import XCTest
@testable import Kima

@MainActor
final class QueueEditingTests: XCTestCase {

    private func controller() -> PlaybackController {
        PlaybackController(server: KimaServer(baseURL: URL(string: "http://test.local")!))
    }

    private func shuffled() throws -> PlaybackController {
        let c = controller()
        c.queue = [try Track.fixture("a"), try Track.fixture("b"), try Track.fixture("c"), try Track.fixture("d")]
        c.isShuffle = true
        c.shuffleOrder = [2, 0, 3, 1]
        c.shufflePosition = 1
        c.currentIndex = 0
        return c
    }

    func testClearUpcomingUnderShuffle() throws {
        let c = try shuffled()
        c.clearUpcoming()
        XCTAssertEqual(c.queue.map(\.id), ["a", "c"])
        XCTAssertEqual(c.shuffleOrder, [1, 0])
        XCTAssertEqual(c.shufflePosition, 1)
        XCTAssertEqual(c.currentIndex, 0)
    }

    func testMoveWithDuplicateIdsKeepsCurrentEntry() throws {
        let c = controller()
        c.queue = [try Track.fixture("a"), try Track.fixture("a"), try Track.fixture("b")]
        c.currentIndex = 1
        c.moveInQueue(fromPlayPositions: [2], toPlayPosition: 0)
        XCTAssertEqual(c.queue.map(\.id), ["b", "a", "a"])
        XCTAssertEqual(c.currentIndex, 2)
    }
}
