import Foundation
import simd

/// One stipple dot along the song path's row, 64 bytes; mirrors `ChartAttr` in `VibeShaders.metal`.
/// Four `SIMD4<Float>`s, each 16-byte aligned, so Swift's layout matches Metal's.
struct VibeChartDot {
    var posAlpha: SIMD4<Float>             // xyz world position, w baked alpha
    var levelAlongSizeScale: SIMD4<Float>  // lod level, glint order (2j), end star's size, end star's glow
    var endPosClear: SIMD4<Float>          // xyz end star's position, w clear radius, points
    var moodPad: SIMD4<Float>              // x end star's mood index (-1 none)
}

/// The song path's row of dots between its two ends: dots step out from each star, fade with distance from it, stop
/// short of the discs, and thin out as the camera zooms out (the shader compares each dot's level to the screen spacing).
enum VibeChart {
    /// The faint starlight row of dots between the song path's two ends; empty until both are on the map.
    static func buildPathChord(startId: String?, endId: String?, indexById: [String: Int],
                               positions: [SIMD3<Float>], sizes: [Float], goals: [Float], moods: [Float],
                               baseSize: Float) -> [VibeChartDot] {
        guard let a = startId.flatMap({ indexById[$0] }), let b = endId.flatMap({ indexById[$0] }), a != b,
              let sid = startId, let eid = endId else { return [] }
        var out = [VibeChartDot]()
        addSegment(from: a, to: b, ids: (sid, eid), base: VibeMapStyle.pathChordAlpha,
                   positions: positions, sizes: sizes, goals: goals, moods: moods,
                   clear: { _ in VibeMapStyle.chartClearSelected },
                   step: baseSize * VibeMapStyle.chartStepFactor, into: &out)
        return out
    }

    /// Dots along one segment at world step `step`, fading out past the reach from the nearer end
    /// (the web loop: `count = floor(length / step)`, dots for j = 1..<count).
    private static func addSegment(from a: Int, to b: Int, ids: (String, String), base: Float,
                                   positions: [SIMD3<Float>], sizes: [Float], goals: [Float], moods: [Float],
                                   clear: (String) -> Float, step: Float, into out: inout [VibeChartDot]) {
        guard a != b else { return }
        let pa = positions[a], delta = positions[b] - pa
        let count = Int(floor(simd_length(delta) / max(step, 1e-4)))
        guard count > 1 else { return }
        let total = Float(count) * step
        for j in 1..<count {
            let off = Float(j) * step
            let fromA = off, fromB = Float(count - j) * step
            let alpha = base * fade(min(fromA, fromB))
            guard alpha > 0.004 else { continue }
            // LOD: a dot's level is the log of the largest run of dots it survives in; dots near a
            // segment's middle keep the highest levels and are the last to drop when zoomed out.
            let k = min(j, count - j)
            let level: Float = k == 1 ? 8 : min(8, log2(Float(k & -k)))
            let (end, endId): (Int, String) = 2 * j <= count ? (a, ids.0) : (b, ids.1)
            out.append(VibeChartDot(posAlpha: SIMD4(pa + delta * (off / total), alpha),
                                    levelAlongSizeScale: SIMD4(level, Float(2 * j), sizes[end],
                                                                1 + 0.6 * (goals[end] - 1)),
                                    endPosClear: SIMD4(positions[end], clear(endId)),
                                    moodPad: SIMD4(moods[end], 0, 0, 0)))
        }
    }

    /// Dots travelling farther from an end than the chart's reach fade out exponentially (web `fade`).
    private static func fade(_ fromEnd: Float) -> Float {
        fromEnd <= VibeMapStyle.chartReach ? 1
            : exp(-(fromEnd - VibeMapStyle.chartReach) / (VibeMapStyle.chartReach * 0.45))
    }
}
