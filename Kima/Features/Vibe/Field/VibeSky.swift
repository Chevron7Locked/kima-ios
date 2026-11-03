import Foundation
import simd

/// The far background stars: directions only, drawn "at infinity". They turn with the camera when it
/// orbits but never move when it pans or zooms, which is what makes them read as far away.
/// Not pickable, not counted, never labelled. Index-based and fixed forever.
enum VibeSky {
    /// Unit direction of far star `k`, uniform on the sphere.
    static func direction(_ k: Int) -> SIMD3<Float> {
        let y = 2 * VibeField.hash01(k, 31) - 1
        let phi = 2 * Double.pi * VibeField.hash01(k, 32)
        let s = (1 - y * y).squareRoot()
        return SIMD3(Float(s * cos(phi)), Float(y), Float(s * sin(phi)))
    }

    /// Whether far star `k` is one of the brighter tenth.
    static func isBright(_ k: Int) -> Bool { VibeField.hash01(k, 33) < 0.10 }

    /// Two float4 per star: [dir, twinkle amplitude] [linear colour, phase].
    static func buffer(count: Int = VibeMapStyle.farStarCount) -> [SIMD4<Float>] {
        var out = [SIMD4<Float>]()
        out.reserveCapacity(count * 2)
        for k in 0..<count {
            let b = isBright(k) ? 0.40 + 0.25 * VibeField.hash01(k, 34) : 0.10 + 0.20 * VibeField.hash01(k, 34)
            let base = VibeField.hash01(k, 35) < 0.25 ? VibeMapStyle.farCool : VibeMapStyle.starlight
            let colour = base * (VibeMapStyle.starColourScale * Float(b))
            let twAmp = Float(0.20 + 0.30 * VibeField.hash01(k, 36))
            let phase = Float(2 * Double.pi * VibeField.hash01(k, 37))
            out.append(SIMD4(direction(k), twAmp))
            out.append(SIMD4(colour, phase))
        }
        return out
    }
}
