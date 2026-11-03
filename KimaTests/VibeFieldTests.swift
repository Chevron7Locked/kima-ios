import XCTest
import simd
@testable import Kima

final class VibeHashTests: XCTestCase {
    func testHashMatchesWebExactly() {
        XCTAssertEqual(VibeField.hash01(0, 1), 0.9693620929028839)
        XCTAssertEqual(VibeField.hash01(1, 1), 0.700961401918903)
        XCTAssertEqual(VibeField.hash01(7, 4), 0.6438422601204365)
        XCTAssertEqual(VibeField.hash01(9026, 5), 0.0661553624086082)
        XCTAssertEqual(VibeField.hash01(123, 2), 0.151519981212914)
    }
}

final class VibeFieldTests: XCTestCase {
    func testToWorld() {
        XCTAssertEqual(VibeField.toWorld(x: 0, y: 0, z: 0), SIMD3<Float>(-60, -60, -60))
        XCTAssertEqual(VibeField.toWorld(x: 1, y: 0.5, z: 0.25), SIMD3<Float>(60, -30, 0))
    }

    func testSyntheticMapFraming() {
        let f = VibeField(tracks: VibeSyntheticMap.tracks())
        XCTAssertEqual(f.centre.x, 0.1726, accuracy: 1e-3)
        XCTAssertEqual(f.centre.y, 0.2285, accuracy: 1e-3)
        XCTAssertEqual(f.centre.z, -0.9878, accuracy: 1e-3)
        XCTAssertEqual(f.radius, 53.9195, accuracy: 1e-3)
        XCTAssertEqual(f.positions[0].x, -35.7678, accuracy: 1e-3)
        XCTAssertEqual(f.positions[0].y, 6.0914, accuracy: 1e-3)
        XCTAssertEqual(f.positions[0].z, -23.3725, accuracy: 1e-3)
    }

    func testBaseSizeAndMoods() {
        // The web's baseSize: 5 / n^0.12, clamped into [0.7, 2.4].
        XCTAssertEqual(VibeField(tracks: VibeSyntheticMap.tracks(count: 6)).baseSize, 2.4, accuracy: 1e-4)
        let big = VibeField(tracks: VibeSyntheticMap.tracks(count: 1000))
        XCTAssertEqual(big.baseSize, Float(5.0 / pow(1000.0, 0.12)), accuracy: 1e-4)
        let f = VibeField(tracks: VibeSyntheticMap.tracks())
        XCTAssertEqual(f.moods.count, 400)
        // The right body's every-tenth "neutral" track has no mood key, so -1 is a valid mood.
        XCTAssertTrue(f.moods.allSatisfy { $0 == -1 || $0 < Float(VibeField.moodKeys.count) })
        XCTAssertTrue(f.moods.contains { $0 == -1 })
    }

    func testStarColourIsStarlightTimesHalfBrightness() {
        let tracks = VibeSyntheticMap.tracks()
        let f = VibeField(tracks: tracks)
        let seed = Int(VibeField.fnv1a32(tracks[5].id))
        let notable = VibeField.hash01(seed, 6) < 0.11
        let h7 = VibeField.hash01(seed, 7)
        let b = notable ? Float(0.70 + 0.30 * h7)
            : VibeMapStyle.faintLow + (VibeMapStyle.faintHigh - VibeMapStyle.faintLow) * Float(h7)
        let expected = VibeMapStyle.starlight * (0.5 * b)
        XCTAssertEqual(f.colours[5].x, expected.x, accuracy: 1e-5)
        XCTAssertEqual(f.colours[5].y, expected.y, accuracy: 1e-5)
        XCTAssertEqual(f.colours[5].z, expected.z, accuracy: 1e-5)
    }

    func testFnv1aKnownValues() {
        XCTAssertEqual(VibeField.fnv1a32(""), 2166136261)
        XCTAssertEqual(VibeField.fnv1a32("a"), 0xe40c292c)
    }

    func testNotableShareIsAboutEleven() {
        var n = 0
        let total = 9027
        for i in 0..<total where VibeField.hash01(Int(VibeField.fnv1a32("track-\(i)")), 6) < 0.11 { n += 1 }
        XCTAssertEqual(Double(n) / Double(total), 0.11, accuracy: 0.015)
    }

    func testAttributesDoNotDependOnOrder() {
        let tracks = VibeSyntheticMap.tracks()
        let a = VibeField(tracks: tracks)
        let b = VibeField(tracks: tracks.reversed())
        let n = tracks.count
        for i in 0..<n {
            XCTAssertEqual(a.sizes[i], b.sizes[n - 1 - i], accuracy: 1e-6)
            XCTAssertEqual(a.colours[i], b.colours[n - 1 - i])
        }
    }

    func testStarSeparation() {
        XCTAssertEqual(VibeMapStyle.coreMinPx, 1.1, accuracy: 1e-6)
        XCTAssertEqual(VibeMapStyle.separationPoints(pxPerPt: 3), (2 * 1.1 + 1) / 3, accuracy: 1e-6)
        XCTAssertEqual(VibeMapStyle.separationPoints(pxPerPt: 2), (2 * 1.1 + 1) / 2, accuracy: 1e-6)
    }

    func testRevealNonNegative() {
        let f = VibeField(tracks: VibeSyntheticMap.tracks())
        XCTAssertTrue(f.reveals.allSatisfy { $0 >= 0 })
        XCTAssertGreaterThan(f.revealDuration, 0.3)
    }
}
