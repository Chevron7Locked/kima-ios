import Foundation
import simd

/// One stipple dot along the queue's thread, 64 bytes; mirrors `ChartAttr` in `VibeShaders.metal`.
/// Four `SIMD4<Float>`s, each 16-byte aligned, so Swift's layout matches Metal's.
struct VibeChartDot {
    var posAlpha: SIMD4<Float>             // xyz world position, w baked alpha
    var levelAlongSizeScale: SIMD4<Float>  // lod level, glint order (2j), end star's size, end star's glow
    var endPosClear: SIMD4<Float>          // xyz end star's position, w clear radius, points
    var moodPad: SIMD4<Float>              // x end star's mood index (-1 none)
}

/// The queue's thread as a constellation of dots: dots step along each pair of songs, fade with
/// distance travelled along the path, stop short of the stars' discs, and thin out as the camera
/// zooms out (the shader compares each dot's level to the screen spacing). A port of `buildQueueChart`.
enum VibeChart {
    /// The thread through the queue, centred on the playing track: songs ahead (strong near, fading
    /// by the 60th) and the last songs played (thin). Queue ids not on the map are skipped.
    /// `sizes`, `goals` and `moods` are per star index; `goals` is the emphasis each star is easing
    /// toward, baked here so dots keep clear of the end stars' drawn size.
    static func buildQueue(ids: [String], playingId: String?, selectedId: String?, operationSourceId: String?,
                           indexById: [String: Int], positions: [SIMD3<Float>], sizes: [Float],
                           goals: [Float], moods: [Float], baseSize: Float) -> [VibeChartDot] {
        var order = [Int](), onIds = [String]()
        for id in ids {
            if let i = indexById[id] { order.append(i); onIds.append(id) }
        }
        let n = order.count
        guard n >= 2 else { return [] }
        // Where the playing song sits in the queue's on-map order; -1 when the queue has no playing song.
        let origin = playingId.flatMap { indexById[$0] }.flatMap { pid in order.firstIndex(of: pid) } ?? -1
        let step = baseSize * VibeMapStyle.chartStepFactor
        func clearPt(_ id: String) -> Float {
            if id == playingId { return VibeMapStyle.chartClearPlaying }
            if id == selectedId { return VibeMapStyle.chartClearSelected }
            if id == operationSourceId { return VibeMapStyle.chartClearOperation }
            return VibeMapStyle.chartClearQueued
        }

        var out = [VibeChartDot]()
        // Ahead: the songs after the playing one, up to 60. The first 8 stay at full strength,
        // then the thread fades to the web's 0.14 by the 60th.
        let a = max(0, origin)
        for i in a..<min(n - 1, a + VibeMapStyle.chartAhead) {
            let o = Float(i - origin)
            let base = o < Float(VibeMapStyle.chartAlphaLast) ? VibeMapStyle.chartAlphaNear
                : lerp(VibeMapStyle.chartAlphaNear, VibeMapStyle.chartAlphaFar,
                       (o - Float(VibeMapStyle.chartAlphaLast)) / VibeMapStyle.chartAlphaFade)
            addSegment(from: order[i], to: order[i + 1], ids: (onIds[i], onIds[i + 1]), base: base,
                       positions: positions, sizes: sizes, goals: goals, moods: moods,
                       clear: clearPt, step: step, into: &out)
        }
        // Played: the last few songs behind the playing one, thin.
        for i in max(0, origin - VibeMapStyle.chartBehind)..<max(0, min(n - 1, origin)) {
            let o = Float(i - origin)
            let base = VibeMapStyle.chartPlayedBase * (1 + (o + 1) / 3)
            addSegment(from: order[i], to: order[i + 1], ids: (onIds[i], onIds[i + 1]), base: base,
                       positions: positions, sizes: sizes, goals: goals, moods: moods,
                       clear: clearPt, step: step, into: &out)
        }
        return out
    }

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

    /// Dots along one segment at world step `step`, fading out as they travel past the reach from
    /// each end (the web loop: `count = floor(length / step)`, dots for j = 1..<count).
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
            guard fromA < VibeMapStyle.chartReach, fromB < VibeMapStyle.chartReach else { continue }
            let alpha = base * fade(fromA) * fade(fromB)
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

    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * min(1, max(0, t))
    }
}
