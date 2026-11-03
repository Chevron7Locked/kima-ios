import XCTest
@testable import Kima

final class StatsShapeMathTests: XCTestCase {
    typealias M = StatsShapeMath

    func testCellCentreAndBuckets() {
        XCTAssertEqual(M.cellCentre(1), 6.1083, accuracy: 0.001)
        XCTAssertEqual(M.cellCentre(12), 48.0917, accuracy: 0.001)
        XCTAssertEqual(M.cellCentre(24), 93.8917, accuracy: 0.001)
        for b in 1...24 { XCTAssertEqual(M.bucketAt(M.cellCentre(b)), b) }
        XCTAssertEqual(M.bucketAt(0), 1)
        XCTAssertEqual(M.bucketAt(100), 24)
    }

    func testDots() {
        XCTAssertEqual(M.dotRadius(plays: 10, max: 10), 2.8, accuracy: 0.01)
        XCTAssertEqual(M.dotRadius(plays: 25, max: 100), 1.75, accuracy: 0.01)
        XCTAssertEqual(M.dotOpacity(plays: 25, max: 100), 0.55, accuracy: 0.01)
    }

    func testWords() {
        XCTAssertEqual(M.energyWord(0.39), "low energy")
        XCTAssertEqual(M.energyWord(0.4), "medium energy")
        XCTAssertEqual(M.energyWord(0.6), "medium energy")
        XCTAssertEqual(M.energyWord(0.61), "high energy")
        XCTAssertEqual(M.brightnessWord(0.3), "dark")
        XCTAssertEqual(M.brightnessWord(0.5), "neutral")
        XCTAssertEqual(M.brightnessWord(0.7), "bright")
    }

    func testOverallAndBarest() throws {
        let o = try XCTUnwrap(M.overall([(24, 1, 5)]))
        XCTAssertEqual(o.valence, 0.9792, accuracy: 0.001)
        XCTAssertEqual(o.energy, 0.0208, accuracy: 0.001)
        XCTAssertNil(M.overall([]))
        let b1 = try XCTUnwrap(M.barest([(20, 20, 100)]))
        XCTAssertEqual(b1.name, "dark, low energy"); XCTAssertEqual(b1.percent, 0)
        XCTAssertNil(M.barest([(5, 5, 50), (20, 5, 50), (5, 20, 50), (20, 20, 50)]))
        let b3 = try XCTUnwrap(M.barest([(5, 5, 2), (20, 5, 98), (5, 20, 100), (20, 20, 100)]))
        XCTAssertEqual(b3.name, "dark, low energy"); XCTAssertEqual(b3.percent, 1)
    }

    func testMovementAndMonths() {
        XCTAssertEqual(M.movement([("2025-09", 0.5, 0.5), ("2025-10", 0.55, 0.5), ("2025-11", 0.6, 0.4)]),
                       "since september 2025: higher energy, darker")
        XCTAssertEqual(M.movement([("2025-09", 0.5, 0.5), ("2025-10", 0.51, 0.49), ("2025-11", 0.51, 0.49)]),
                       "no change since september 2025")
        XCTAssertNil(M.movement([("2025-09", 0.5, 0.5), ("2025-10", 0.55, 0.5)]))
        XCTAssertEqual(M.monthLong("2025-09"), "september 2025")
        XCTAssertEqual(M.monthShort("2025-09"), "sep 25")
        XCTAssertEqual(M.monthShort("2026-01"), "jan 26")
    }
}
