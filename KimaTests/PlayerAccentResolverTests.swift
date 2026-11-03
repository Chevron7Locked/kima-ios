import XCTest
import SwiftUI
@testable import Kima

final class PlayerAccentResolverTests: XCTestCase {
    func testColourGivesGradientAccent() {
        let r = PlayerAccentResolver.resolve(trackId: "a") { _ in 0.92 }
        XCTAssertEqual(r.accent.color, FilamentAccent(colour: 0.92).color)
        XCTAssertTrue(r.hasColour)
    }

    func testNoColourFallsBackToBrand() {
        let r = PlayerAccentResolver.resolve(trackId: "a") { _ in nil }
        XCTAssertEqual(r.accent, FilamentAccent.brand)
        XCTAssertFalse(r.hasColour)
    }

    func testNoTrackFallsBackToBrand() {
        let r = PlayerAccentResolver.resolve(trackId: nil) { _ in 0.5 }
        XCTAssertEqual(r.accent, FilamentAccent.brand)
        XCTAssertFalse(r.hasColour)
    }
}
