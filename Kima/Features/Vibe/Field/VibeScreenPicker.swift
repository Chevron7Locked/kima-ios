import Foundation
import simd

/// Finds the star drawn nearest a touch. Every star is projected once per
/// camera pose into a 32-point grid, so a pick is a few lookups even with 100,000 stars.
final class VibeScreenPicker {
    static let cell: Float = 32
    /// Touch reach in points: half a 44-pt touch target (the web's 12 px is for a mouse).
    static let pickRadius: Float = 22

    private let positions: [SIMD3<Float>]
    private var sx: [Float], sy: [Float], depth: [Float]
    private var cells = [Int: [Int]]()
    private var cols = 1
    private var poseKey: (simd_float4x4, SIMD2<Float>)?

    init(positions: [SIMD3<Float>]) {
        self.positions = positions
        sx = [Float](repeating: .nan, count: positions.count)
        sy = sx
        depth = sx
    }

    private static func same(_ a: simd_float4x4, _ b: simd_float4x4) -> Bool {
        a.columns.0 == b.columns.0 && a.columns.1 == b.columns.1
            && a.columns.2 == b.columns.2 && a.columns.3 == b.columns.3
    }

    /// Re-project when the view-projection matrix or the view size changed.
    func refresh(viewProjection vp: simd_float4x4, width: Float, height: Float) {
        let size = SIMD2<Float>(width, height)
        if let k = poseKey, k.1 == size, Self.same(k.0, vp) { return }
        poseKey = (vp, size)
        let cell = Self.cell
        cols = Int((width / cell).rounded(.up)) + 1
        cells.removeAll(keepingCapacity: true)
        for i in 0..<positions.count {
            let c = vp * SIMD4(positions[i], 1)
            guard c.w > 0 else { sx[i] = .nan; continue }
            let z = c.z / c.w
            guard z >= 0, z <= 1 else { sx[i] = .nan; continue }
            let x = (c.x / c.w + 1) / 2 * width
            let y = (1 - c.y / c.w) / 2 * height
            sx[i] = x; sy[i] = y; depth[i] = z
            if x < -cell || y < -cell || x > width + cell || y > height + cell { continue }
            let k = Int(((y + cell) / cell).rounded(.down)) * cols + Int(((x + cell) / cell).rounded(.down))
            cells[k, default: []].append(i)
        }
    }

    /// Index of the star nearest (x, y) within `radius` points. Closer to the camera breaks near-ties.
    func pick(viewProjection vp: simd_float4x4, width: Float, height: Float, x: Float, y: Float,
              radius: Float = VibeScreenPicker.pickRadius) -> Int? {
        refresh(viewProjection: vp, width: width, height: height)
        let cell = Self.cell
        let c0 = Int(((x - radius + cell) / cell).rounded(.down)), c1 = Int(((x + radius + cell) / cell).rounded(.down))
        let r0 = Int(((y - radius + cell) / cell).rounded(.down)), r1 = Int(((y + radius + cell) / cell).rounded(.down))
        var best: Int?, bestScore = Float.infinity
        for r in r0...max(r0, r1) {
            for c in c0...max(c0, c1) {
                guard let bucket = cells[r * cols + c] else { continue }
                for i in bucket {
                    let d = hypot(sx[i] - x, sy[i] - y)
                    if d > radius { continue }
                    let score = d + (2 * depth[i] - 1) * 2
                    if score < bestScore { bestScore = score; best = i }
                }
            }
        }
        return best
    }

    /// Screen position of star `i` for the last pose, or NaN when it is off camera.
    func screenOf(_ i: Int, viewProjection vp: simd_float4x4, width: Float, height: Float) -> CGPoint {
        refresh(viewProjection: vp, width: width, height: height)
        guard i >= 0, i < positions.count, !sx[i].isNaN else { return CGPoint(x: CGFloat.nan, y: CGFloat.nan) }
        return CGPoint(x: CGFloat(sx[i]), y: CGFloat(sy[i]))
    }
}
