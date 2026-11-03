import CoreGraphics
import Foundation
import simd

/// Decides which mood labels show: off-screen or behind-camera
/// labels hide, and going biggest first, a label overlapping one already placed hides.
enum VibeLabelLayout {
    struct Item {
        /// Centre in view points.
        var centre: CGPoint
        /// Normalised device coordinates, -1...1.
        var ndc: SIMD2<Float>
        /// False when the anchor is behind the camera or past the far plane.
        var inFront: Bool
        /// Label box size in points.
        var size: CGSize
    }

    static let edge: Float = 0.86
    static let padX: CGFloat = 6
    static let padY: CGFloat = 4

    /// Project a world point for layout. `size` is the label's box.
    static func item(world: SIMD3<Float>, viewProjection vp: simd_float4x4, viewSize: CGSize, size: CGSize) -> Item {
        let c = vp * SIMD4(world, 1)
        let front = c.w > 0 && c.z / c.w <= 1
        let ndc = c.w != 0 ? SIMD2(c.x / c.w, c.y / c.w) : SIMD2<Float>(repeating: 0)
        let centre = CGPoint(x: CGFloat((ndc.x + 1) / 2) * viewSize.width, y: CGFloat((1 - ndc.y) / 2) * viewSize.height)
        return Item(centre: centre, ndc: ndc, inFront: front, size: size)
    }

    /// One flag per item, in the order given (biggest mood first): true to show.
    static func visibility(_ items: [Item]) -> [Bool] {
        var placed = [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)]()
        return items.map { it in
            guard it.inFront, abs(it.ndc.x) < edge, abs(it.ndc.y) < edge else { return false }
            let w = it.size.width / 2 + padX, h = it.size.height / 2 + padY
            if placed.contains(where: { abs($0.x - it.centre.x) < $0.w + w && abs($0.y - it.centre.y) < $0.h + h }) {
                return false
            }
            placed.append((it.centre.x, it.centre.y, w, h))
            return true
        }
    }
}
