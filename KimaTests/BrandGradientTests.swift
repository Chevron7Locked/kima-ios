import XCTest
import SwiftUI
@testable import Kima

/// Expected values come from running the web's `brandColourAt` (sRGB per-channel blend, rounded).
final class BrandGradientTests: XCTestCase {

    private func hex(_ share: Double) -> String {
        String(format: "%06x", KimaBrandGradient.hex(at: share))
    }

    func testEndpoints() {
        XCTAssertEqual(hex(1), "fca506")
        XCTAssertEqual(hex(0), "0191c9")
    }

    func testClampsOutsideRange() {
        XCTAssertEqual(hex(2), "fca506")
        XCTAssertEqual(hex(-1), "0191c9")
    }

    func testEveryStopIsExactAtItsPosition() {
        XCTAssertEqual(KimaBrandGradient.stops.count, 14)
        for stop in KimaBrandGradient.stops {
            XCTAssertEqual(KimaBrandGradient.hex(at: 1 - stop.position), stop.hex,
                           String(format: "stop %.2f", stop.position))
        }
    }

    func testBlendedValuesMatchTheWebFormula() {
        XCTAssertEqual(hex(0.92), "fdab13")
        XCTAssertEqual(hex(0.06), "0389cb")
        XCTAssertEqual(hex(0.5), "ba3cb6")
        XCTAssertEqual(hex(0.65), "ef7d81")
        XCTAssertEqual(hex(0.33), "5438d7")
    }

    func testAccentColourMatchesGradient() {
        let a = FilamentAccent(colour: 0.5)
        XCTAssertEqual(a.color, KimaBrandGradient.color(at: 0.5))
    }
}
