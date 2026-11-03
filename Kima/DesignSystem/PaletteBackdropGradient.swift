import SwiftUI

// MARK: - PaletteBackdropGradient

/// Shared top-to-bottom hero gradient driven by a `CoverArtPalette`: vibrant, darkVibrant,
/// darkMuted, then `KimaColor.base` at the bottom (stop locations/opacities are parameters).
/// Without a palette (loading or unavailable) the `fallback*` colours are used at the same
/// opacities; pass pre-multiplied fallbacks if you want them dimmer.
struct PaletteBackdropGradient: View {

    let palette: CoverArtPalette?

    // MARK: Fallback colours

    /// Top-band fallback when palette is nil.
    /// May carry a pre-multiplied opacity for a dimmer loading-state appearance.
    var fallbackTop:   Color = KimaColor.ambient.opacity(0.35)
    var fallbackMid:   Color = KimaColor.ambient.opacity(0.18)
    var fallbackLow:   Color = KimaColor.base

    // MARK: Stop opacities (applied to both palette and fallback colours)

    var topOpacity:    Double = 0.30
    var midOpacity:    Double = 0.60
    var lowerOpacity:  Double = 0.90

    // MARK: Stop locations

    /// Location of the mid stop.   Default 0.50.
    var stop1: Double = 0.50
    /// Location of the lower stop. Default 0.85.
    var stop2: Double = 0.85

    // MARK: - Body

    // A-9: when Reduce Transparency is on, use an opaque solid base instead of a
    // layered semi-transparent gradient so contrast and readability are maximised.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            KimaColor.base
        } else {
            gradient
        }
    }

    private var gradient: some View {
        let top  = palette.map(\.vibrant)      ?? fallbackTop
        let mid  = palette.map(\.darkVibrant)  ?? fallbackMid
        let low  = palette.map(\.darkMuted)    ?? fallbackLow
        return LinearGradient(
            stops: [
                .init(color: top.opacity(topOpacity),   location: 0.00),
                .init(color: mid.opacity(midOpacity),   location: stop1),
                .init(color: low.opacity(lowerOpacity), location: stop2),
                .init(color: KimaColor.base,             location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Palette wash card

extension View {
    /// A padded card on the surface colour with a faint `tint` wash from the top-leading corner
    /// and a hairline border. Used by Discover's featured pick and Search's top result.
    func kimaPaletteWashCard(tint: Color) -> some View {
        padding(KimaSpacing.lg)
            .background(
                ZStack {
                    KimaColor.surface
                    LinearGradient(
                        colors: [tint.opacity(0.10), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                    .strokeBorder(KimaColor.hairline, lineWidth: 1)
            )
    }
}
