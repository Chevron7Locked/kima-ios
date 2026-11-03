import XCTest
@testable import Kima

final class StatsClockMathTests: XCTestCase {
    private typealias M = StatsClockMath

    private func zero() -> [[Int]] { Array(repeating: Array(repeating: 0, count: 24), count: 7) }

    func testFullInk() {
        var c = zero()
        for i in 0..<20 { c[i / 4][i % 4] = i + 1 }
        XCTAssertEqual(M.fullInk(c), 18)
        XCTAssertEqual(M.fullInk(zero()), 1)
        var one = zero(); one[3][3] = 7
        XCTAssertEqual(M.fullInk(one), 7)
    }

    func testInkOpacity() {
        XCTAssertEqual(M.inkOpacity(0, full: 18), 0)
        XCTAssertEqual(M.inkOpacity(18, full: 18), 1.0)
        XCTAssertEqual(M.inkOpacity(36, full: 18), 1.0)
        XCTAssertEqual(M.inkOpacity(9, full: 18), 0.6464, accuracy: 0.001)
    }

    func testBusiestBreaksTiesByDayThenHour() {
        var c = zero()
        c[4][15] = 51; c[2][20] = 30; c[6][10] = 30; c[0][9] = 5
        let r = M.busiest(c)
        XCTAssertEqual(r.map(\.cell), [M.Cell(dow: 4, hour: 15), M.Cell(dow: 2, hour: 20), M.Cell(dow: 6, hour: 10)])
        XCTAssertEqual(r.map(\.plays), [51, 30, 30])
    }

    func testPercentOfAll() {
        XCTAssertEqual(M.percentOfAll(51, total: 643), "7.9")
        XCTAssertEqual(M.percentOfAll(1, total: 0), "0.0")
    }

    func testColumnCentre() {
        XCTAssertEqual(Double(M.columnCentre(hour: 0, width: 300, spacing: 2)), 5.2917, accuracy: 0.001)
        XCTAssertEqual(Double(M.columnCentre(hour: 6, width: 300, spacing: 2)), 80.7917, accuracy: 0.001)
        XCTAssertEqual(Double(M.columnCentre(hour: 23, width: 300, spacing: 2)), 294.7083, accuracy: 0.001)
    }
}
