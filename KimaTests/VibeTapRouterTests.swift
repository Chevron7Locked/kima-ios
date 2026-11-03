import XCTest
@testable import Kima

final class VibeTapRouterTests: XCTestCase {

    private func act(_ id: String?, picking: Bool = false) -> VibeTapAction {
        VibeTapRouter.action(for: id, state: .init(pickingPath: picking))
    }

    func testSongPathWaitingForAnEndFillsItAndIgnoresEmptySpace() {
        XCTAssertEqual(act("t", picking: true), .pickPathTrack("t"))
        XCTAssertEqual(act(nil, picking: true), .ignore)
    }

    func testIdle() {
        XCTAssertEqual(act("t"), .select("t"))
        XCTAssertEqual(act(nil), .deselect)
    }
}
