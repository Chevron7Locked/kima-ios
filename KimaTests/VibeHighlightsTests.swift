import XCTest
@testable import Kima

final class VibeHighlightsTests: XCTestCase {

    private func input() -> VibeHighlights.Input {
        var i = VibeHighlights.Input()
        i.searchIds = ["s1", "s2"]
        i.similarIds = ["m1"]
        i.pinnedIds = ["p1", "p2"]
        return i
    }

    func testSearchWinsOverEverything() { XCTAssertEqual(VibeHighlights.ids(input()), ["s1", "s2"]) }

    func testSimilarWinsOverAPin() {
        var i = input(); i.searchIds = []
        XCTAssertEqual(VibeHighlights.ids(i), ["m1"])
    }

    func testPinnedChipLightsItsStarsWhenNothingElseIsShowing() {
        var i = input(); i.searchIds = []; i.similarIds = []
        XCTAssertEqual(VibeHighlights.ids(i), ["p1", "p2"])
    }

    func testEmpty() {
        XCTAssertEqual(VibeHighlights.ids(VibeHighlights.Input()), [])
    }
}
