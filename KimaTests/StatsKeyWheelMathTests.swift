import XCTest
import CoreGraphics
@testable import Kima

final class StatsKeyWheelMathTests: XCTestCase {
    private typealias M = StatsKeyWheelMath
    private typealias W = StatsKeyWheelMath.Wedge
    private let c = CGPoint(x: 150, y: 150)
    private let R: CGFloat = 150

    private func hit(_ x: Double, _ y: Double) -> W? {
        M.hitTest(CGPoint(x: x, y: y), center: c, radius: R)
    }
    private func lp(_ i: Int, _ r: M.Ring) -> CGPoint { M.labelPoint(index: i, ring: r, center: c, radius: R) }

    func testHitTestCardinals() {
        XCTAssertEqual(hit(150, 32.25), W(index: 0, ring: .major))
        XCTAssertEqual(hit(267.75, 150), W(index: 3, ring: .major))
        XCTAssertEqual(hit(150, 267.75), W(index: 6, ring: .major))
        XCTAssertEqual(hit(32.25, 150), W(index: 9, ring: .major))
        XCTAssertEqual(hit(150, 75.75), W(index: 0, ring: .minor))
    }

    func testHitTestOutsideRings() {
        XCTAssertNil(hit(150, 150))
        XCTAssertNil(hit(150, -7.5))
    }

    func testWedgeBoundary() {
        func at(_ d: Double) -> W? {
            let a = d * .pi / 180
            return hit(150 + cos(a) * 117.75, 150 + sin(a) * 117.75)
        }
        XCTAssertEqual(at(-76)?.index, 0)
        XCTAssertEqual(at(-74)?.index, 1)
    }

    func testLabelPoints() {
        XCTAssertEqual(Double(lp(3, .major).x), 267.75, accuracy: 0.01)
        XCTAssertEqual(Double(lp(3, .major).y), 150, accuracy: 0.01)
        XCTAssertEqual(Double(lp(0, .major).x), 150, accuracy: 0.01)
        XCTAssertEqual(Double(lp(0, .major).y), 32.25, accuracy: 0.01)
        XCTAssertEqual(Double(lp(1, .major).x), 208.875, accuracy: 0.01)
        XCTAssertEqual(Double(lp(1, .major).y), 48.03, accuracy: 0.01)
        XCTAssertEqual(Double(lp(6, .minor).x), 150, accuracy: 0.01)
        XCTAssertEqual(Double(lp(6, .minor).y), 224.25, accuracy: 0.01)
    }

    func testMajorLabelsDoNotPileUp() {
        var minD = Double.infinity
        for i in 0..<12 {
            for j in (i + 1)..<12 {
                let a = lp(i, .major), b = lp(j, .major)
                minD = min(minD, Double(hypot(a.x - b.x, a.y - b.y)))
            }
        }
        XCTAssertEqual(minD, 60.95, accuracy: 0.05)
    }

    func testCountsKeepScalesApart() {
        let k = M.counts([("A", "minor", 10), ("C", "major", 5), ("Gb", "major", 3), ("F#", "major", 2),
                          ("C#", "minor", 4), ("Db", "minor", 1), ("D#", "minor", 2), ("A#", "major", 3)])
        XCTAssertEqual(k.major[0], 5)
        XCTAssertEqual(k.major[6], 5)
        XCTAssertEqual(k.major[3], 0)
        XCTAssertEqual(k.major[10], 3)
        XCTAssertEqual(k.minor[0], 10)
        XCTAssertEqual(k.minor[4], 5)
        XCTAssertEqual(k.minor[6], 2)
    }

    func testShadeMaths() {
        XCTAssertEqual(M.share(0, max: 10), 0)
        XCTAssertEqual(M.share(10, max: 10), 1)
        XCTAssertEqual(M.share(5, max: 10), 0.6598, accuracy: 0.001)
        XCTAssertEqual(M.fillOpacity(5, max: 10), 0.7006, accuracy: 0.001)
        XCTAssertTrue(M.isLoud(5, max: 10))
        XCTAssertFalse(M.isLoud(4, max: 10))
    }

    func testNames() {
        XCTAssertEqual(M.label(index: 7, ring: .major), "db")
        XCTAssertEqual(M.label(index: 0, ring: .minor), "am")
        XCTAssertEqual(M.label(index: 4, ring: .minor), "c#m")
        XCTAssertEqual(M.displayName(index: 0, ring: .major), "c major")
        XCTAssertEqual(M.displayName(index: 4, ring: .minor), "c# minor")
        XCTAssertEqual(M.displayName(index: 7, ring: .major), "db major")
        XCTAssertEqual(M.apiKey(index: 0, ring: .minor), "A minor")
        XCTAssertEqual(M.apiKey(index: 4, ring: .minor), "C# minor")
        XCTAssertEqual(M.apiKey(index: 6, ring: .major), "F# major")
    }
}
