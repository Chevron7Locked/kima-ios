import XCTest
import simd
@testable import Kima

final class VibeMoodAnchorsTests: XCTestCase {
    func testSyntheticAnchors() {
        let tracks = VibeSyntheticMap.tracks()
        XCTAssertEqual(VibeMoodAnchors.minCount(trackCount: tracks.count), 8)
        let a = VibeMoodAnchors.compute(tracks: tracks)
        XCTAssertEqual(a.map(\.label), ["intense", "calm", "melancholic"])
        XCTAssertEqual(a.map(\.count), [180, 100, 100])
        let expected: [(Double, Double, Double)] = [(0.7628, 0.4211, 0.4306), (0.2594, 0.3924, 0.3957), (0.1049, 0.5767, 0.5930)]
        for (anchor, e) in zip(a, expected) {
            XCTAssertEqual(anchor.x, e.0, accuracy: 1e-3)
            XCTAssertEqual(anchor.y, e.1, accuracy: 1e-3)
            XCTAssertEqual(anchor.z, e.2, accuracy: 1e-3)
        }
        XCTAssertFalse(a.contains { $0.mood == "neutral" })
    }

    func testJsRoundGoesUpOnHalves() {
        XCTAssertEqual(VibeMoodAnchors.jsRound(2.5), 3)
        XCTAssertEqual(VibeMoodAnchors.jsRound(2.4), 2)
    }
}
