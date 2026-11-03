import XCTest
import simd
@testable import Kima

final class VibeStarMetricsTests: XCTestCase {
    func testSmallStarAtHomeDepthSitsOnTheFloor() {
        XCTAssertEqual(VibeStarMetrics.pointSizePt(size: 1.0, depth: 100, home: 100), 1.1, accuracy: 1e-5)
    }

    func testLargerStarAtHomeDepth() {
        XCTAssertEqual(VibeStarMetrics.pointSizePt(size: 2.0, depth: 100, home: 100), 2.0886, accuracy: 1e-3)
    }

    func testGrowthFollowsDepth() {
        // Size 1 ten times closer grows tenfold, uncapped (the web's 1/depth behaviour).
        XCTAssertEqual(VibeStarMetrics.pointSizePt(size: 1, depth: 10, home: 100), 1.0443 * 10, accuracy: 1e-4)
    }

    func testMaximumIsTwentyPoints() {
        XCTAssertEqual(VibeStarMetrics.pointSizePt(size: 2, depth: 10, home: 100), 20, accuracy: 1e-6)
        XCTAssertEqual(VibeStarMetrics.pointSizePt(size: 50, depth: 1, home: 100), 20, accuracy: 1e-6)
    }

    func testGrowthCapGuardsStarsAtTheCamera() {
        // Only a star passing through the camera reaches the growth cap; the size clamp binds first.
        XCTAssertEqual(VibeStarMetrics.pointSizePt(size: 1, depth: 0.5, home: 100), 20, accuracy: 1e-6)
    }

    func testQuietStarsShrink() {
        let full = VibeStarMetrics.pointSizePt(size: 4, depth: 100, home: 100)
        let quiet = VibeStarMetrics.pointSizePt(size: 4, depth: 100, home: 100, emph: 0.28)
        XCTAssertEqual(quiet / full, 1 + 0.6 * (0.28 - 1), accuracy: 1e-4)
    }

    func testUniformsMatchTheShaderLayout() {
        XCTAssertEqual(MemoryLayout<VibeShaderUniforms>.size, 304)
        XCTAssertEqual(MemoryLayout<VibeShaderUniforms>.offset(of: \.starlight), 160)
        XCTAssertEqual(MemoryLayout<VibeShaderUniforms>.offset(of: \.viewSize), 208)
        XCTAssertEqual(MemoryLayout<VibeShaderUniforms>.offset(of: \.maxPt), 240)
        XCTAssertEqual(MemoryLayout<VibeShaderUniforms>.offset(of: \.focusMood), 244)
        XCTAssertEqual(MemoryLayout<VibeShaderUniforms>.offset(of: \.projScaleY), 248)
        XCTAssertEqual(MemoryLayout<VibeShaderUniforms>.offset(of: \.chartStep), 264)
        XCTAssertEqual(MemoryLayout<VibeShaderUniforms>.offset(of: \.focusColourMix), 288)
    }

    func testChartDotMatchesTheShaderLayout() {
        XCTAssertEqual(MemoryLayout<VibeChartDot>.stride, 64)
        XCTAssertEqual(MemoryLayout<VibeChartDot>.offset(of: \.levelAlongSizeScale), 16)
        XCTAssertEqual(MemoryLayout<VibeChartDot>.offset(of: \.endPosClear), 32)
        XCTAssertEqual(MemoryLayout<VibeChartDot>.offset(of: \.moodPad), 48)
    }

    func testStarRecordMatchesTheShaderLayout() {
        XCTAssertEqual(MemoryLayout<VibeStarAttr>.stride, 48)
        XCTAssertEqual(MemoryLayout<VibeStarAttr>.offset(of: \.colourPhase), 16)
        XCTAssertEqual(MemoryLayout<VibeStarAttr>.offset(of: \.twinkleReveal), 32)    }
}

final class VibeSkyTests: XCTestCase {
    func testDirectionsAreUnitAndStable() {
        for k in [0, 1, 500, 4095] {
            XCTAssertEqual(simd_length(VibeSky.direction(k)), 1, accuracy: 1e-4)
            XCTAssertEqual(VibeSky.direction(k), VibeSky.direction(k))
        }
    }

    func testBufferHoldsTwoVectorsPerStar() {
        XCTAssertEqual(VibeSky.buffer().count, 2 * VibeMapStyle.farStarCount)
    }
}
