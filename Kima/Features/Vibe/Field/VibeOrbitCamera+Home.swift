import Foundation
import simd

/// Where the home camera sits and how far it may pull back.
struct VibeHomePose: Equatable {
    let target: SIMD3<Float>
    /// Unit direction from the target to the camera.
    let back: SIMD3<Float>
    let distance: Float
}

extension VibeOrbitCamera {

    // MARK: Home framing

    /// The camera looks at the mean of the stars from a fixed polar angle, turned so the long axis runs
    /// up a portrait screen. The distance fits 95% of the stars, capped at 1.5 times the distance that
    /// fits 80%, so a few far-out tracks cannot shrink the bulk. Only the camera moves, never a star.
    static func homePose(positions: [SIMD3<Float>], aspect: Float) -> VibeHomePose {
        let tanHalf = tan(fovDegrees * .pi / 180 / 2)
        guard !positions.isEmpty else {
            return VibeHomePose(target: .zero, back: SIMD3(0, 1, 0), distance: 60 / tanHalf)
        }
        let n = Double(positions.count)
        var sum = SIMD3<Double>(repeating: 0)
        for p in positions { sum += SIMD3<Double>(p) }
        let mean = sum / n
        var sxx = 0.0, szz = 0.0, sxz = 0.0
        for p in positions {
            let dx = Double(p.x) - mean.x, dz = Double(p.z) - mean.z
            sxx += dx * dx; szz += dz * dz; sxz += dx * dz
        }
        let a = 0.5 * atan2(2 * sxz, sxx - szz)
        var h = SIMD3<Float>(Float(cos(a)), 0, Float(sin(a)))
        if aspect >= 1 { h = SIMD3(-h.z, 0, h.x) }

        let target = SIMD3<Float>(mean)
        var along = positions.map { simd_dot($0, h) }.sorted()
        let lo = along[Int(Double(along.count - 1) * 0.05)], hi = along[Int(Double(along.count - 1) * 0.95)]
        along.removeAll()
        let skew = simd_dot(target, h) - (lo + hi) / 2
        if abs(skew) > 0.01 * (hi - lo) {
            if skew < 0 { h = -h }
        } else if h.z < 0 || (h.z == 0 && h.x < 0) {
            h = -h
        }
        let polar = VibeMapStyle.homePolar
        let theta = atan2(h.x, h.z)
        let back = SIMD3<Float>(sin(polar) * sin(theta), cos(polar), sin(polar) * cos(theta))

        let forward = -back
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        var need = [Float]()
        need.reserveCapacity(positions.count)
        for p in positions {
            let o = p - target
            let across = abs(simd_dot(o, right)) / (tanHalf * aspect * VibeMapStyle.fillAcross)
            let upward = abs(simd_dot(o, up)) / (tanHalf * VibeMapStyle.fillUp)
            need.append(simd_dot(o, back) + max(across, upward))
        }
        need.sort()
        func pct(_ q: Double) -> Float { need[Int(Double(need.count - 1) * q)] }
        let d = max(1, min(pct(VibeMapStyle.framePercentile), VibeMapStyle.frameTailCap * pct(0.80)))
        return VibeHomePose(target: target, back: back, distance: d)
    }

    /// A flat map (almost no spread up and down) may not be orbited down to the horizon or up over the pole.
    static func polarRange(positions: [SIMD3<Float>], centre: SIMD3<Float>) -> ClosedRange<Float> {
        guard positions.count > 1 else { return polarEpsilon...(.pi - polarEpsilon) }
        var vertical = [Float](), horizontal = [Float]()
        for p in positions {
            vertical.append(abs(p.y - centre.y))
            horizontal.append(simd_length(SIMD2(p.x - centre.x, p.z - centre.z)))
        }
        vertical.sort(); horizontal.sort()
        let i = Int(Double(positions.count - 1) * 0.95)
        if vertical[i] < 0.05 * horizontal[i] { return VibeMapStyle.flatPolarRange }
        return polarEpsilon...(.pi - polarEpsilon)
    }

    // MARK: Zoom-out limit ("never a blob")

    /// Share of on-screen stars with another on-screen star closer than `n` points, with the camera at
    /// `target + back * d`, plus how many stars are on screen.
    static func closeStats(positions: [SIMD3<Float>], target: SIMD3<Float>, back: SIMD3<Float>, d: Float,
                           viewSize: SIMD2<Float>, n: Float) -> (share: Float, onScreen: Int) {
        let aspect = viewSize.y > 0 ? viewSize.x / viewSize.y : 1
        let vp = projectionMatrix(aspect: aspect) * viewMatrix(position: target + back * d, target: target)
        let w = viewSize.x, h = viewSize.y
        var xs = [Float](), ys = [Float]()
        for p in positions {
            let c = vp * SIMD4(p, 1)
            guard c.w > near else { continue }
            let nx = c.x / c.w, ny = c.y / c.w
            guard nx >= -1, nx < 1, ny > -1, ny <= 1 else { continue }
            xs.append((nx + 1) / 2 * w)
            ys.append((1 - ny) / 2 * h)
        }
        let kept = xs.count
        guard kept >= 2, n > 0 else { return (0, kept) }
        let cols = Int(w / n) + 2
        var grid = [Int: [Int]]()
        for i in 0..<kept {
            grid[Int(ys[i] / n) * cols + Int(xs[i] / n), default: []].append(i)
        }
        let n2 = n * n
        var close = 0
        for i in 0..<kept {
            let cx = Int(xs[i] / n), cy = Int(ys[i] / n)
            var found = false
            search: for gy in (cy - 1)...(cy + 1) {
                for gx in (cx - 1)...(cx + 1) {
                    guard let cell = grid[gy * cols + gx] else { continue }
                    for j in cell where j != i {
                        let dx = xs[i] - xs[j], dy = ys[i] - ys[j]
                        if dx * dx + dy * dy < n2 { found = true; break search }
                    }
                }
            }
            if found { close += 1 }
        }
        return (Float(close) / Float(kept), kept)
    }

    static func closeShare(positions: [SIMD3<Float>], target: SIMD3<Float>, back: SIMD3<Float>, d: Float,
                           viewSize: SIMD2<Float>, n: Float) -> Float {
        closeStats(positions: positions, target: target, back: back, d: d, viewSize: viewSize, n: n).share
    }

    /// The farthest distance whose close share is at most one half: the median star keeps at least `n`
    /// points between it and its nearest on-screen neighbour. Bisection on log distance, 24 steps.
    static func zoomOutLimit(positions: [SIMD3<Float>], target: SIMD3<Float>, back: SIMD3<Float>,
                             framing: Float, viewSize: SIMD2<Float>, n: Float) -> Float {
        func share(_ d: Float) -> Float {
            closeShare(positions: positions, target: target, back: back, d: d, viewSize: viewSize, n: n)
        }
        var lo = 0.05 * framing, hi = 4 * framing
        if share(lo) > 0.5 { return lo }
        if share(hi) <= 0.5 { return hi }
        for _ in 0..<24 {
            let mid = (lo * hi).squareRoot()
            if share(mid) <= 0.5 { lo = mid } else { hi = mid }
        }
        return lo
    }
}
