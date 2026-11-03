import Foundation

/// A star's drawn size in points, from the same `VibeMapStyle` constants the shader receives.
/// Kept in Swift so the size rule is covered by unit tests.
enum VibeStarMetrics {
    /// `size` is the star's own size (about 0.7 to 2.3), `depth` its distance from the camera, `home` the
    /// camera's home distance and `emph` the emphasis multiplier.
    static func pointSizePt(size: Float, depth: Float, home: Float, emph: Float = 1) -> Float {
        let grow = min(home / max(depth, 0.001), VibeMapStyle.starGrowthCap)
        let glow = 1 + 0.6 * (emph - 1)
        let pt = size * VibeMapStyle.starSizeK * grow * glow
        return min(max(pt, VibeMapStyle.starMinPt), VibeMapStyle.starMaxPt)
    }
}
