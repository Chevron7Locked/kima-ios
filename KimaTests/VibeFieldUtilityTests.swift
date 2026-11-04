import XCTest
import simd
@testable import Kima

final class VibeScreenPickerTests: XCTestCase {
    /// An identity-style projection: clip x,y = world x,y mapped so that world (a, b) lands at a known screen point.
    /// Screen (w=200,h=200): world x = (sx/100 - 1), y = (1 - sy/100), depth z in 0...1, w = 1.
    private func vp() -> simd_float4x4 { matrix_identity_float4x4 }
    private func star(sx: Float, sy: Float, z: Float) -> SIMD3<Float> { SIMD3(sx / 100 - 1, 1 - sy / 100, z) }

    func testPicksWithinTwentyTwoPoints() {
        let picker = VibeScreenPicker(positions: [star(sx: 100, sy: 100, z: 0.5)])
        XCTAssertEqual(picker.pick(viewProjection: vp(), width: 200, height: 200, x: 110, y: 100), 0)
        XCTAssertNil(picker.pick(viewProjection: vp(), width: 200, height: 200, x: 130, y: 100))
    }

    func testNearerStarWins() {
        let picker = VibeScreenPicker(positions: [star(sx: 100, sy: 100, z: 0.9), star(sx: 100, sy: 100, z: 0.2)])
        XCTAssertEqual(picker.pick(viewProjection: vp(), width: 200, height: 200, x: 100, y: 100), 1)
    }

    func testStarBehindCameraNeverPicked() {
        var flip = matrix_identity_float4x4
        flip.columns.3.w = -1 // w = -1: behind the camera
        let picker = VibeScreenPicker(positions: [star(sx: 100, sy: 100, z: 0.5)])
        XCTAssertNil(picker.pick(viewProjection: flip, width: 200, height: 200, x: 100, y: 100))
        let p = picker.screenOf(0, viewProjection: flip, width: 200, height: 200)
        XCTAssertTrue(p.x.isNaN)
    }

    func testPickFromRealCamera() {
        let field = VibeField(tracks: VibeSyntheticMap.tracks())
        let cam = VibeOrbitCamera(field: field, viewSize: SIMD2(400, 800))
        let picker = VibeScreenPicker(positions: field.positions)
        let vp = cam.viewProjection
        let s = picker.screenOf(10, viewProjection: vp, width: 400, height: 800)
        XCTAssertFalse(s.x.isNaN)
        XCTAssertNotNil(picker.pick(viewProjection: vp, width: 400, height: 800, x: Float(s.x), y: Float(s.y)))
    }
}

final class VibeEmphasisTests: XCTestCase {
    private let ids = ["a": 0, "b": 1, "c": 2, "d": 3]

    private func goals(h: Set<String> = [], sel: String? = nil, play: String? = nil) -> [Float] {
        VibeEmphasis.goals(count: 4, indexById: ids, highlighted: h, selected: sel, playing: play)
    }

    func testNoStateIsAllOne() { XCTAssertEqual(goals(), [1, 1, 1, 1]) }

    func testSelectionOnly() { XCTAssertEqual(goals(sel: "b"), [0.6, 1.7, 0.6, 0.6]) }

    func testHighlights() { XCTAssertEqual(goals(h: ["a", "c"]), [1.35, 0.12, 1.35, 0.12]) }

    func testPlayingIsAtLeastOnePointFiveAndSelectionWins() {
        XCTAssertEqual(goals(h: ["a"], play: "a")[0], 1.5)
        XCTAssertEqual(goals(h: ["a"], play: "b")[1], 1.5)
        XCTAssertEqual(goals(play: "c")[2], 1.5)
        XCTAssertEqual(goals(sel: "c", play: "c")[2], 1.7)
    }

    func testEasingConvergesAndSettles() {
        var e = VibeEmphasis(count: 4)
        let g = goals(h: ["a"])
        var settled = false
        var frames = 0
        while !settled && frames < 1000 { settled = e.ease(toward: g, dt: 1 / 60, reduceMotion: false); frames += 1 }
        XCTAssertTrue(settled)
        XCTAssertEqual(e.values, g)
    }

    func testReduceMotionSnapsInOneStep() {
        var e = VibeEmphasis(count: 4)
        _ = e.ease(toward: goals(sel: "a"), dt: 1 / 60, reduceMotion: true)
        XCTAssertEqual(e.values, [1.7, 0.6, 0.6, 0.6])
    }
}

final class VibeChartTests: XCTestCase {
    // Eight stars in a row one world unit apart; baseSize 2.4 puts dots 0.36 units apart,
    // one per gap (count = floor(1 / 0.36) = 2, one dot between the stars).
    private let positions: [SIMD3<Float>] = (0..<8).map { SIMD3(Float($0), 0, 0) }
    private var index: [String: Int] { Dictionary(uniqueKeysWithValues: (0..<8).map { ("s\($0)", $0) }) }
    private var sizes: [Float] { [Float](repeating: 1, count: 8) }
    private var goals: [Float] { [Float](repeating: 1, count: 8) }
    private var moods: [Float] { [Float](repeating: -1, count: 8) }

    func testPathChordIsStarlightAndFaint() {
        let dots = VibeChart.buildPathChord(startId: "s0", endId: "s1", indexById: index,
                                            positions: positions, sizes: sizes, goals: goals,
                                            moods: moods, baseSize: 2.4)
        XCTAssertEqual(dots.count, 1)
        XCTAssertEqual(dots[0].posAlpha.w, VibeMapStyle.pathChordAlpha, accuracy: 1e-6)
    }

    func testDotsStopShortOfStarDiscs() {
        let dots = VibeChart.buildPathChord(startId: "s0", endId: "s1", indexById: index,
                                            positions: positions, sizes: sizes, goals: goals,
                                            moods: moods, baseSize: 2.4)
        XCTAssertEqual(dots[0].endPosClear.x, 0)          // nearer end wins
        XCTAssertEqual(dots[0].endPosClear.w, VibeMapStyle.chartClearSelected, accuracy: 1e-6)
    }

    func testALongChordStaysAttachedToBothStars() {
        // Ends 100 units apart, far past the reach: dots leave each star and none float in the gap.
        let ends: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(100, 0, 0)]
        let dots = VibeChart.buildPathChord(startId: "a", endId: "b", indexById: ["a": 0, "b": 1],
                                            positions: ends, sizes: [1, 1], goals: [1, 1], moods: [-1, -1],
                                            baseSize: 2.4)
        XCTAssertFalse(dots.isEmpty)
        XCTAssertEqual(dots.map(\.posAlpha.x).min() ?? 0, 0.36, accuracy: 0.01)
        XCTAssertEqual(dots.map(\.posAlpha.x).max() ?? 0, 99.64, accuracy: 1e-1)
        XCTAssertTrue(dots.allSatisfy { min($0.posAlpha.x, 100 - $0.posAlpha.x) < 4 * VibeMapStyle.chartReach })
    }
}

final class VibeRingsTests: XCTestCase {
    // Identity camera: view space = world space, so depth = -z. Stars sit at z = -100, home = 100.
    private let view = matrix_identity_float4x4
    private var viewSize: CGSize { CGSize(width: 400, height: 800) }

    private func build(_ ids: [String], _ positions: [SIMD3<Float>], sizes: [Float], emph: [Float],
                       playingId: String?, selectedId: String?,
                       operationSourceId: String? = nil, queueIds: [String] = []) -> [VibeRing] {
        let index = Dictionary(uniqueKeysWithValues: zip(ids, ids.indices))
        return VibeRings.build(indexById: index, positions: positions, sizes: sizes, emph: emph,
                               view: view, viewProj: view, viewSize: viewSize, home: 100,
                               operationSourceId: operationSourceId, playingId: playingId,
                               selectedId: selectedId, queueIds: queueIds)
    }

    func testRingsTrackTheStarDisc() {
        // Size 2 at depth 100 draws 2.0886 pt; its core disc is 0.375948 pt.
        let positions: [SIMD3<Float>] = [SIMD3(0, 0, -100), SIMD3(10, 0, -100), SIMD3(20, 0, -100)]
        let rings = build(["a", "b", "c"], positions, sizes: [2, 2, 2], emph: [1, 1, 1],
                          playingId: "b", selectedId: "c", operationSourceId: "a")
        XCTAssertEqual(rings.count, 5)
        // Operation ring: disc + 10 gap, stroke 1.
        XCTAssertEqual(rings[0].outerRadius, 0.375948 + 10 + 0.5, accuracy: 1e-4)
        XCTAssertEqual(rings[0].opacity, 0.45)
        XCTAssertEqual(rings[0].colour, VibeMapStyle.starlight)
        // The selection's dark moat sits under the playing ring, between its white and amber rings.
        XCTAssertEqual(rings[1].outerRadius, 0.375948 + 1.5 + 1, accuracy: 1e-4)
        XCTAssertEqual(rings[1].colour, VibeMapStyle.ink)
        XCTAssertEqual(rings[1].centre, positions[2])
        XCTAssertEqual(rings[2].outerRadius, 0.375948 + 6.5 + 0.625, accuracy: 1e-4)
        XCTAssertEqual(rings[2].opacity, 0.7)
        XCTAssertTrue(rings[2].breathes)
        XCTAssertEqual(rings[2].centre, positions[1])
        XCTAssertEqual(rings[3].outerRadius, 0.375948 + 3 + 0.5, accuracy: 1e-4)
        XCTAssertEqual(rings[3].colour, SIMD3<Float>(1, 1, 1))
        XCTAssertEqual(rings[4].outerRadius, 0.375948 + 6.5 + 0.625, accuracy: 1e-4)
        XCTAssertEqual(rings[4].colour, VibeMapStyle.amber)
    }

    func testRingsGrowWithZoom() {
        // Ten times closer: the core disc grows 10x (clamped at the star's 20 pt cap).
        let positions: [SIMD3<Float>] = [SIMD3(0, 0, -10)]
        let rings = build(["a"], positions, sizes: [2], emph: [1], playingId: "a", selectedId: nil)
        XCTAssertEqual(rings.count, 1)
        XCTAssertEqual(rings[0].outerRadius, 3.6 + 6.5 + 0.625, accuracy: 1e-4)
    }

    func testQueueRingsOnTheFirstSongsAhead() {
        let positions: [SIMD3<Float>] = (0..<4).map { SIMD3(Float($0) * 10, 0, -100) }
        let ids = ["p", "s1", "s2", "s3"]
        let rings = build(ids, positions, sizes: [2, 2, 2, 2], emph: [1, 1, 1, 1],
                          playingId: "p", selectedId: nil, queueIds: ids)
        XCTAssertEqual(rings.count, 4)   // the playing star's amber ring, then songs 1, 2, 3
        XCTAssertEqual(rings[0].colour, VibeMapStyle.amber)
        XCTAssertEqual(rings[0].opacity, 0.7)
        let opacities: [Float] = [0.47, 0.44, 0.41]
        for (ring, expected) in zip(rings.dropFirst(), opacities) {
            XCTAssertEqual(ring.opacity, expected, accuracy: 1e-6)
        }
        XCTAssertEqual(rings[1].colour, VibeMapStyle.queue)
        XCTAssertEqual(rings[1].outerRadius, 0.375948 + 4.5 + 0.375, accuracy: 1e-4)
    }

    func testCrowdedSongLosesItsRing() {
        // Songs 1 and 2 land 1 pt apart on screen: the second is crowded out.
        let positions: [SIMD3<Float>] = [SIMD3(0, 0, -100), SIMD3(0.005, 0, -100), SIMD3(0.01, 0, -100)]
        let ids = ["p", "s1", "s2"]
        let rings = build(ids, positions, sizes: [2, 2, 2], emph: [1, 1, 1],
                          playingId: "p", selectedId: nil, queueIds: ids)
        XCTAssertEqual(rings.count, 1)
    }

    func testBlendQueueDrawsNoOperationRing() {
        let positions: [SIMD3<Float>] = [SIMD3(1, 2, -3)]
        let rings = VibeRings.build(indexById: ["a": 0], positions: positions, sizes: [1], emph: [1],
                                    view: matrix_identity_float4x4, viewProj: matrix_identity_float4x4,
                                    viewSize: CGSize(width: 100, height: 100), home: 100,
                                    operationSourceId: "a", playingId: nil, selectedId: nil,
                                    operationKind: .blend)
        XCTAssertTrue(rings.isEmpty)
    }

    func testMissingIdsDrawNothingAndBreathStopsUnderReduceMotion() {
        XCTAssertTrue(VibeRings.build(indexById: [:], positions: [], sizes: [], emph: [],
                                      view: matrix_identity_float4x4, viewProj: matrix_identity_float4x4,
                                      viewSize: CGSize(width: 100, height: 100), home: 100,
                                      operationSourceId: "x", playingId: "y", selectedId: "z").isEmpty)
        XCTAssertEqual(VibeRings.breathOpacity(time: 1, reduceMotion: true), 0.7)
        XCTAssertNotEqual(VibeRings.breathOpacity(time: 1, reduceMotion: false), 0.7)
        for t in stride(from: Float(0), to: 6.4, by: 0.1) {
            let o = VibeRings.breathOpacity(time: t, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(o, 0.55 - 1e-5)
            XCTAssertLessThanOrEqual(o, 0.75 + 1e-5)
        }
    }
}

final class VibeLabelLayoutTests: XCTestCase {
    private func item(_ x: Float, _ y: Float = 0, front: Bool = true) -> VibeLabelLayout.Item {
        VibeLabelLayout.Item(centre: CGPoint(x: CGFloat((x + 1) * 100), y: CGFloat((1 - y) * 100)),
                             ndc: SIMD2(x, y), inFront: front, size: CGSize(width: 60, height: 20))
    }

    func testNearEdgeHidden() { XCTAssertEqual(VibeLabelLayout.visibility([item(0.9), item(0.5)]), [false, true]) }

    func testOverlapHidesSecond() {
        XCTAssertEqual(VibeLabelLayout.visibility([item(0.0), item(0.05)]), [true, false])
        XCTAssertEqual(VibeLabelLayout.visibility([item(-0.5), item(0.5)]), [true, true])
    }

    func testBehindCameraHidden() { XCTAssertEqual(VibeLabelLayout.visibility([item(0, front: false)]), [false]) }

    func testProjectedItem() {
        let it = VibeLabelLayout.item(world: SIMD3(0, 0, 0.5), viewProjection: matrix_identity_float4x4,
                                      viewSize: CGSize(width: 200, height: 200), size: CGSize(width: 10, height: 10))
        XCTAssertTrue(it.inFront)
        XCTAssertEqual(it.centre.x, 100, accuracy: 1e-3)
        XCTAssertEqual(it.centre.y, 100, accuracy: 1e-3)
    }
}
