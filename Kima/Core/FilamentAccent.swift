import SwiftUI
import UIKit

// MARK: - FilamentAccent

/// A resolved accent triple derived from the current track's mood blend.
/// `color` is the primary adaptive accent; `bright` and `deep` are derived
/// lighter/darker variants for highlights and shadows.
struct FilamentAccent: Equatable {
    var color: Color
    var bright: Color
    var deep: Color

    /// Static AMBER brand accent: the resting value of `env.accent` before a mood-tagged track
    /// plays. Mirrors `KimaColor.brand` / `.brandBright` / `.brandDeep`.
    static let brand = FilamentAccent(
        color:  KimaColor.brand,
        bright: KimaColor.brandBright,
        deep:   KimaColor.brandDeep
    )
}

// MARK: - Gradient accent

extension FilamentAccent {
    /// The accent for a track's map `colour` (0 azure ... 1 amber): the logo-gradient colour, with
    /// lighter and darker variants blended toward white and black.
    init(colour: Double) {
        let base = KimaBrandGradient.uiColor(at: colour)
        self.init(
            color:  Color(uiColor: base),
            bright: Color(uiColor: Self.lighten(base, amount: 0.18)),
            deep:   Color(uiColor: Self.darken(base, amount: 0.22))
        )
    }

    /// Lighten toward white by blending with white in RGB space.
    private static func lighten(_ c: UIColor, amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(
            red:   min(1, r + (1 - r) * amount),
            green: min(1, g + (1 - g) * amount),
            blue:  min(1, b + (1 - b) * amount),
            alpha: 1
        )
    }

    /// Darken toward black by scaling RGB channels down.
    private static func darken(_ c: UIColor, amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        let s = 1 - amount
        return UIColor(
            red:   max(0, r * s),
            green: max(0, g * s),
            blue:  max(0, b * s),
            alpha: 1
        )
    }
}
