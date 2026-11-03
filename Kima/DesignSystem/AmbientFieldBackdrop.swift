import SwiftUI

// MARK: - AmbientFieldBackdrop

/// App-wide ambient backdrop: a static violet sky (near-black bleeding to #160b1c at the top) that content and glass chrome float over.
/// The current track's cover art adds a brightness-normalised glow (saturated and pale covers land at the same gentle strength).
/// Reduce Transparency switches to a solid base colour.
/// Usage: `AmbientFieldBackdrop(palette: env.ambientPalette).ignoresSafeArea()` in `KimaScreenGround`.
struct AmbientFieldBackdrop: View {

    /// The resolved palette from `CoverArtColor.palette(coverId:server:)`.
    /// `nil` when nothing is playing or the cover art has no palette.
    let palette: CoverArtPalette?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // The violet cosmos ramp — warm near-black that bleeds to violet at the top, then deepens.
    private let cosmos = Gradient(stops: [
        .init(color: Color(hex: 0x160B1C), location: 0.00),   // violet bleed at the top
        .init(color: Color(hex: 0x0B0510), location: 0.35),   // warm near-black
        .init(color: Color(hex: 0x050209), location: 0.70),
        .init(color: Color(hex: 0x020104), location: 1.00),   // pure near-black
    ])
    // A faint ambient violet nebula bloom near the top — depth, not a lamp.
    private let nebula = Color(red: 119/255, green: 59/255, blue: 151/255)
    /// The bloom's opacity every 100pt out from its centre, to 1000pt.
    private static let bloomFalloff: [Double] = [0.256, 0.240, 0.199, 0.144, 0.092, 0.052, 0.025, 0.011, 0.004, 0.001, 0]

    // MARK: - Body

    var body: some View {
        if reduceTransparency {
            KimaColor.base
        } else {
            ZStack {
                LinearGradient(
                    gradient: cosmos,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                // An overlay, so the wide bloom never changes the screen's layout width.
                .overlay {
                    // A 400pt disc under a 260pt blur, drawn as its falloff: a blur filter this size is redrawn
                    // on every frame anything above it moves, which costs scrolling frames on every screen.
                    RadialGradient(stops: Self.bloomFalloff.enumerated().map { i, a in
                        .init(color: nebula.opacity(a), location: CGFloat(i) / CGFloat(Self.bloomFalloff.count - 1))
                    }, center: .center, startRadius: 0, endRadius: 1000)
                    .frame(width: 2000, height: 2000)
                    .offset(y: -520)
                    .opacity(0.28)
                    .allowsHitTesting(false)
                }
                if let p = palette {
                    coverGlow(for: p)
                }
            }
        }
    }

    /// A soft radial of the CURRENT cover's colour at top-centre — layers the playing track's hue
    /// onto the sunrise. Normalised so a saturated cover doesn't blow out the wash.
    private func coverGlow(for p: CoverArtPalette) -> some View {
        let c = normalizeWash(p.vibrant)
        // The glow's reach is a proportion of the space this backdrop actually occupies, so it
        // follows iPad split view / Stage Manager windows instead of the whole screen.
        return GeometryReader { geo in
            RadialGradient(
                colors: [c.opacity(0.18), c.opacity(0.04), .clear],
                center: UnitPoint(x: 0.5, y: 0.02),
                startRadius: 20,
                endRadius: max(geo.size.width, geo.size.height) * 0.65
            )
        }
    }

    // MARK: - Brightness normalisation

    /// Clamp a cover colour's HSL so the glow is a gentle, even wash regardless of the cover:
    /// lightness into a fixed band, saturation capped. Keeps it "ambient", never "vivid".
    private func normalizeWash(_ color: Color) -> Color {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)

        let hsl = toHSL(r: r, g: g, b: b)
        let normalizedL = min(0.55, max(0.28, hsl.lightness))
        let normalizedS = min(hsl.saturation, 0.60)
        let rgb = rgbFromHSL(hue: hsl.hue, saturation: normalizedS, lightness: normalizedL)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    // MARK: - HSL helpers

    private func toHSL(r: CGFloat, g: CGFloat, b: CGFloat) -> (hue: CGFloat, saturation: CGFloat, lightness: CGFloat) {
        let max = max(r, g, b)
        let min = min(r, g, b)
        var h: CGFloat = 0
        var s: CGFloat = 0
        let l = (max + min) / 2

        if max != min {
            let d = max - min
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
            switch max {
            case r: h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
            case g: h = (b - r) / d + 2
            default: h = (r - g) / d + 4
            }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, s, l)
    }

    private func rgbFromHSL(hue: CGFloat, saturation: CGFloat, lightness: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        if saturation == 0 { return (lightness, lightness, lightness) }
        let q = lightness < 0.5
            ? lightness * (1 + saturation)
            : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        return (
            hueAt(p, q, hue + CGFloat(1) / CGFloat(3)),
            hueAt(p, q, hue),
            hueAt(p, q, hue - CGFloat(1) / CGFloat(3))
        )
    }

    private func hueAt(_ p: CGFloat, _ q: CGFloat, _ t: CGFloat) -> CGFloat {
        var t = t
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < CGFloat(1) / CGFloat(6) { return p + (q - p) * 6 * t }
        if t < CGFloat(1) / CGFloat(2) { return q }
        if t < CGFloat(2) / CGFloat(3) { return p + (q - p) * (CGFloat(2) / CGFloat(3) - t) * 6 }
        return p
    }
}
