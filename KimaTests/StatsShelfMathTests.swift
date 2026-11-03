import XCTest
@testable import Kima

final class StatsShelfMathTests: XCTestCase {
    typealias M = StatsShelfMath

    func testDecadeLabel() {
        XCTAssertEqual(M.decadeLabel(1970), "70s")
        XCTAssertEqual(M.decadeLabel(2000), "00s")
        XCTAssertEqual(M.decadeLabel(2010), "10s")
    }

    func testDecadeSummary() {
        let r = M.decadeSummary([(1970, 4, 0), (1990, 40, 30), (2000, 10, 9), (2010, 2, 0)])
        XCTAssertEqual(r?.biggest, 1990)
        XCTAssertEqual(r?.coldest, 1970)
        XCTAssertNil(M.decadeSummary([]))
    }

    func testDecadeSentence() {
        XCTAssertEqual(M.decadeSentence(biggest: 1990, coldest: 1970), "most albums: 90s · least played: 70s")
        XCTAssertEqual(M.decadeSentence(biggest: 1990, coldest: nil), "most albums: 90s")
        XCTAssertEqual(M.decadeSentence(biggest: 1990, coldest: 1990), "most albums: 90s")
    }

    func testNearestIndex() {
        XCTAssertEqual(M.nearestIndex(x: 50, centres: [10, 40, 90]), 1)
        XCTAssertNil(M.nearestIndex(x: 0, centres: []))
    }

    func testSegmentWidths() {
        let a = M.segmentWidths([600, 300, 100], total: 1000, width: 302, gap: 2)
        XCTAssertEqual(a[0], 178.8, accuracy: 0.01)
        XCTAssertEqual(a[1], 89.4, accuracy: 0.01)
        XCTAssertEqual(a[2], 29.8, accuracy: 0.01)
        let b = M.segmentWidths([995, 5], total: 1000, width: 302, gap: 2)
        XCTAssertEqual(b[0], 298.5, accuracy: 0.01)
        XCTAssertEqual(b[1], 2.0, accuracy: 0.01)
    }

    func testHarderPercent() {
        XCTAssertEqual(M.harderPercent(owned: 0.5, played: 0.6), 20)
        XCTAssertEqual(M.harderPercent(owned: 0.5, played: 0.51), 2)
    }

    func testJoined() {
        XCTAssertEqual(M.joined(["3 finished", nil, "1 untouched 90+ days"]), "3 finished · 1 untouched 90+ days")
        XCTAssertNil(M.joined([nil, nil]))
    }

    func testOwnedLabel() {
        XCTAssertEqual(M.ownedLabel("how hard it hits"), "energy")
        XCTAssertEqual(M.ownedLabel("Something New"), "something new")
    }
}
