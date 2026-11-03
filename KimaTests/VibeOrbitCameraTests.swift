import XCTest
import simd
@testable import Kima

final class VibeOrbitCameraTests: XCTestCase {
    private func makeField() -> VibeField { VibeField(tracks: VibeSyntheticMap.tracks()) }

    private func camera(aspect: Float, field: VibeField) -> VibeOrbitCamera {
        VibeOrbitCamera(field: field, viewSize: SIMD2(aspect * 1000, 1000))
    }

    func testFramingDistanceIsPositiveAndWiderOnPortrait() {
        let f = makeField()
        let portrait = camera(aspect: 0.46, field: f), landscape = camera(aspect: 1.6, field: f)
        XCTAssertGreaterThanOrEqual(portrait.framingDistance, 1)
        XCTAssertGreaterThanOrEqual(landscape.framingDistance, 1)
        XCTAssertEqual(portrait.homeDistance, portrait.framingDistance, accuracy: 1e-4)
        XCTAssertEqual(portrait.maxDistance, portrait.framingDistance, accuracy: 1e-4) // until measured
    }

    func testFramingDistanceHonoursTailCap() {
        // 99 stars in a tight ball and one far outlier: the 95th percentile ignores the outlier.
        var pts = (0..<99).map { i in SIMD3<Float>(Float(i % 10) - 5, Float(i / 10) - 5, 0) }
        pts.append(SIMD3(10_000, 0, 0))
        let pose = VibeOrbitCamera.homePose(positions: pts, aspect: 0.5)
        XCTAssertLessThan(pose.distance, 200)
        XCTAssertGreaterThanOrEqual(pose.distance, 1)
    }

    func testHomeFramesMostStars() {
        let f = makeField()
        for aspect: Float in [0.46, 1.6] {
            let cam = camera(aspect: aspect, field: f)
            let vp = cam.viewProjection
            var inside = 0
            for p in f.positions {
                let c = vp * SIMD4(p, 1)
                if c.w > 0, abs(c.x / c.w) <= 1, abs(c.y / c.w) <= 1 { inside += 1 }
            }
            XCTAssertGreaterThanOrEqual(Double(inside) / Double(f.count), 0.95, "aspect \(aspect)")
        }
    }

    func testHomePolarAngle() {
        let cam = camera(aspect: 0.46, field: makeField())
        XCTAssertEqual(cam.phi, 0.574, accuracy: 1e-3)
        XCTAssertEqual(cam.distance, cam.homeDistance, accuracy: 1e-3)
    }

    func testPolarAngleClamps() {
        var cam = camera(aspect: 1, field: makeField())
        cam.orbit(dx: 0, dy: -100000)
        for _ in 0..<600 { cam.frame(dt: 1 / 60) }
        XCTAssertEqual(cam.phi, cam.phiRange.upperBound, accuracy: 1e-6)
        cam.orbit(dx: 0, dy: 1_000_000)
        for _ in 0..<600 { cam.frame(dt: 1 / 60) }
        XCTAssertEqual(cam.phi, cam.phiRange.lowerBound, accuracy: 1e-6)
    }

    func testPinchRatioTwo() {
        var cam = camera(aspect: 1, field: makeField())
        let r = cam.distance
        cam.pinch(ratio: 2, at: cam.viewSize / 2)
        XCTAssertEqual(cam.distance, r / pow(2, 0.9), accuracy: r * 1e-4)
    }

    func testDistanceClamps() {
        var cam = camera(aspect: 1, field: makeField())
        cam.pinch(ratio: 1e9, at: cam.viewSize / 2)
        XCTAssertEqual(cam.distance, cam.minDistance, accuracy: 1e-3)
        cam.pinch(ratio: 1e-9, at: cam.viewSize / 2)
        XCTAssertEqual(cam.distance, cam.maxDistance, accuracy: 1e-2)
    }

    func testTargetPulledBackToLimit() {
        var cam = camera(aspect: 1, field: makeField())
        let before = cam.position
        cam.target += SIMD3(1000, 0, 0)
        cam.applyLimits()
        XCTAssertEqual(simd_length(cam.target - cam.fieldCentre), cam.fieldRadius * 1.3, accuracy: 1e-2)
        XCTAssertGreaterThan(simd_length(cam.position - before), 1) // the camera moved with the target
        XCTAssertEqual(simd_length(cam.position - cam.target), cam.distance, accuracy: 1e-2)
    }

    func testDampingTakesEightPercentThenAll() {
        var cam = camera(aspect: 1, field: makeField())
        let t0 = cam.theta
        cam.orbit(dx: 10, dy: 0)
        let delta = cam.pendingTheta
        cam.frame(dt: 1 / 60)
        XCTAssertEqual(cam.theta - t0, delta * 0.08, accuracy: abs(delta) * 1e-4)
        for _ in 0..<400 { cam.frame(dt: 1 / 60) }
        XCTAssertEqual(cam.theta - t0, delta, accuracy: abs(delta) * 1e-3)
    }

    func testFlightEasingAndArrival() {
        XCTAssertEqual(VibeOrbitCamera.easeOutExpo(0), 0, accuracy: 1e-6)
        XCTAssertEqual(VibeOrbitCamera.easeOutExpo(1), 1)
        var cam = camera(aspect: 1, field: makeField())
        cam.pinch(ratio: 3, at: cam.viewSize / 2)
        cam.flyHome(reduceMotion: false)
        for _ in 0..<90 { cam.frame(dt: 1 / 60) }
        XCTAssertFalse(cam.isFlying)
        XCTAssertEqual(simd_length(cam.position - cam.homePosition), 0, accuracy: 1e-2)
    }

    func testReduceMotionFlightIsInstant() {
        var cam = camera(aspect: 1, field: makeField())
        cam.pinch(ratio: 3, at: cam.viewSize / 2)
        cam.flyHome(reduceMotion: true)
        cam.frame(dt: 1 / 60)
        XCTAssertFalse(cam.isFlying)
        XCTAssertEqual(simd_length(cam.position - cam.homePosition), 0, accuracy: 1e-2)
    }

    func testCameraMemoryMatchesMapKeyOnly() {
        VibeCameraMemory.clear()
        VibeCameraMemory.save(position: SIMD3(1, 2, 3), target: .zero, mapKey: "a|1|-")
        XCTAssertNil(VibeCameraMemory.pose(for: "b|1|-"))
        XCTAssertEqual(VibeCameraMemory.pose(for: "a|1|-")?.position, SIMD3<Float>(1, 2, 3))
        VibeCameraMemory.clear()
        XCTAssertNil(VibeCameraMemory.pose(for: "a|1|-"))
    }

    // MARK: zoom-out limit

    /// A flat square lattice of `side * side` stars, `spacing` world units apart, around the origin.
    private func lattice(side: Int, spacing: Float) -> [SIMD3<Float>] {
        var out = [SIMD3<Float>]()
        for i in 0..<side { for j in 0..<side {
            out.append(SIMD3((Float(i) - Float(side) / 2) * spacing, 0, (Float(j) - Float(side) / 2) * spacing))
        } }
        return out
    }

    func testZoomOutLimitRule() {
        let pts = lattice(side: 40, spacing: 2)
        let size = SIMD2<Float>(393, 852)
        let n: Float = 12                      // two stars closer than 12 points are "close"
        let back = SIMD3<Float>(0, 1, 0)       // looking straight down
        let framing: Float = 120
        let limit = VibeOrbitCamera.zoomOutLimit(positions: pts, target: .zero, back: back,
                                                 framing: framing, viewSize: size, n: n)
        let inside = VibeOrbitCamera.closeShare(positions: pts, target: .zero, back: back, d: limit * 0.98, viewSize: size, n: n)
        let beyond = VibeOrbitCamera.closeShare(positions: pts, target: .zero, back: back, d: limit * 1.05, viewSize: size, n: n)
        XCTAssertLessThanOrEqual(inside, 0.5)
        XCTAssertGreaterThan(beyond, 0.5)
        XCTAssertGreaterThanOrEqual(limit, 0.05 * framing)
        XCTAssertLessThanOrEqual(limit, 4 * framing)
    }

    func testZoomOutLimitIsClampedToBounds() {
        let size = SIMD2<Float>(393, 852)
        let back = SIMD3<Float>(0, 1, 0)
        // Two stars far apart are never close: the limit is the upper bound, four framing distances.
        let sparse = [SIMD3<Float>(-50, 0, 0), SIMD3<Float>(50, 0, 0)]
        XCTAssertEqual(VibeOrbitCamera.zoomOutLimit(positions: sparse, target: .zero, back: back, framing: 100,
                                                    viewSize: size, n: 1), 400, accuracy: 1e-3)
    }

    func testApplyZoomOutLimitKeepsHomeInside() {
        var cam = camera(aspect: 0.46, field: makeField())
        let framing = cam.framingDistance
        cam.applyZoomOutLimit(framing * 0.5)
        XCTAssertEqual(cam.maxDistance, framing * 0.5, accuracy: 1e-4)
        XCTAssertEqual(cam.homeDistance, framing * 0.5, accuracy: 1e-4)
        XCTAssertLessThanOrEqual(cam.homeDistance, cam.maxDistance)
        cam.applyZoomOutLimit(framing * 2)
        XCTAssertEqual(cam.homeDistance, framing, accuracy: 1e-4)
        XCTAssertEqual(cam.minDistance, cam.homeDistance * 0.12, accuracy: 1e-4)
    }

    func testFlatMapClampsPolarAngle() {
        let flat = (0..<200).map { i in SIMD3<Float>(Float(i % 20) * 3, 0.01, Float(i / 20) * 3) }
        let r = VibeOrbitCamera.polarRange(positions: flat, centre: SIMD3(28, 0.01, 14))
        XCTAssertEqual(r, VibeMapStyle.flatPolarRange)
    }
}
