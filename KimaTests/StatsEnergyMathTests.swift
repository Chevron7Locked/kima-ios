import XCTest
@testable import Kima

final class StatsEnergyMathTests: XCTestCase {
    private typealias M = StatsEnergyMath
    private let sample = M.rows([(8, 2, 0.5), (12, 5, 0.7), (20, 1, 0.6)])

    func testRowsCarryReadings() {
        XCTAssertEqual(sample.count, 24)
        for h in 0...11 { XCTAssertEqual(sample[h].energy, 0.5, accuracy: 1e-9) }
        for h in 12...19 { XCTAssertEqual(sample[h].energy, 0.7, accuracy: 1e-9) }
        for h in 20...23 { XCTAssertEqual(sample[h].energy, 0.6, accuracy: 1e-9) }
        XCTAssertEqual(sample.filter { $0.raw != nil }.map(\.hour), [8, 12, 20])
        XCTAssertEqual(M.playedCount(sample), 3)
    }

    func testNormalized() {
        let n = M.normalized(sample)
        XCTAssertEqual(n[12], 1.0, accuracy: 0.01)
        XCTAssertEqual(n[8], 0.0, accuracy: 0.01)
        XCTAssertEqual(n[20], 0.5, accuracy: 0.01)
        XCTAssertEqual(n[0], 0.0, accuracy: 0.01)
    }

    func testFlatDayIsMidline() {
        let n = M.normalized(M.rows([(1, 1, 0.6), (2, 1, 0.6), (3, 1, 0.6)]))
        for v in n { XCTAssertEqual(v, 0.5, accuracy: 0.01) }
    }

    func testFranticCalmestAndTies() {
        XCTAssertEqual(M.frantic(sample), 12)
        XCTAssertEqual(M.calmest(sample), 8)
        XCTAssertEqual(M.frantic(M.rows([(3, 1, 0.7), (9, 1, 0.7), (10, 1, 0.2)])), 3)
    }
}
