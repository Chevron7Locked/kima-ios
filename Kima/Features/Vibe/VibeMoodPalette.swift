import SwiftUI
import UIKit
import simd

// MARK: - Mood colour palette

/// Mood colours. One table for the whole app: the vibe map's stars and chips, the mood-mixer tiles
/// and the radio cards all key off it (oklch tokens converted to sRGB). The five moods and the
/// neutral/unanalyzed greys below are the full set.
enum VibeMoodPalette {

    // MARK: - Colour table

    /// The web's mood tokens (`globals.css` `--color-mood-*`, oklch converted to sRGB). Mood data colours
    /// on the stars, chips, mixer tiles and card gradients.
    static let mapColors: [String: (r: Double, g: Double, b: Double)] = [
        "moodHappy":      (r: 229, g: 167, b:  75),   // #e5a74b  --happy
        "moodSad":        (r: 126, g:  92, b: 142),   // #7e5c8e  --sad
        "moodRelaxed":    (r:  82, g: 151, b: 150),   // #529796  --relaxed
        "moodAggressive": (r: 193, g:  76, b:  53),   // #c14c35  --aggr
        "moodParty":      (r: 182, g:  94, b: 139),   // #b65e8b  --party
        "neutral":        (r: 163, g: 163, b: 163),   // #a3a3a3
        "unanalyzed":     (r:  96, g:  96, b: 104),   // #606068
    ]

    /// Muted map colour for a mood key (bare or `moodXxx`); unknown keys get neutral. Not brightened.
    static func mapColor(for moodKey: String) -> Color {
        let c = mapColors[paletteKey(forAxis: moodKey)] ?? mapColors["neutral"]!
        return Color(.sRGB, red: c.r / 255, green: c.g / 255, blue: c.b / 255, opacity: 1)
    }

    /// Linear-light colour for the map shader, or nil when `key` is not a palette entry.
    static func linearColour(for key: String) -> SIMD3<Float>? {
        guard let c = mapColors[paletteKey(forAxis: key)] else { return nil }
        let hex = UInt32(c.r) << 16 | UInt32(c.g) << 8 | UInt32(c.b)
        return VibeMapStyle.linear(hex: hex)
    }

    // MARK: - Label map

    /// Plain name for each mood key.
    static let labels: [String: String] = [
        "moodHappy":      "upbeat",
        "moodSad":        "melancholic",
        "moodRelaxed":    "calm",
        "moodAggressive": "intense",
        "moodParty":      "energetic",
        "neutral":        "no single mood",
        "unanalyzed":     "not analysed yet",
    ]

    /// The five real moods, in the order the legend lists them.
    static let moodKeys = ["moodHappy", "moodSad", "moodRelaxed", "moodAggressive", "moodParty"]

    /// True for one of the five moods (bare server names like "happy" count too).
    static func isMood(_ key: String) -> Bool {
        moodKeys.contains(paletteKey(forAxis: key))
    }

    /// Label for any mood key; unknown keys read "no single mood".
    static func label(for key: String) -> String {
        labels[paletteKey(forAxis: key)] ?? "no single mood"
    }
}

extension VibeMoodPalette {

    // MARK: - Backend axis keys

    /// Bare axis names (`"happy"`, `"sad"`, ...) to the `moodHappy`-style keys the tables above use
    /// and the map sends.
    private static let axisToPaletteKey: [String: String] = [
        "happy":      "moodHappy",
        "sad":        "moodSad",
        "relaxed":    "moodRelaxed",
        "party":      "moodParty",
        "aggressive": "moodAggressive",
    ]

    /// Resolves a backend mood key to the tables' key. Bare axis names are mapped; anything else
    /// (`"neutral"`, an already-prefixed key) passes through.
    static func paletteKey(forAxis axis: String) -> String {
        axisToPaletteKey[axis] ?? axis
    }
}

// MARK: - SwiftUI color accessors

extension VibeMoodPalette {

    // MARK: Shared OLED-brightening helper

    /// Boost minimum brightness so a palette colour reads vividly on near-black (max channel ≥ 0.85).
    /// Every call-site uses this one function.
    static func brighten(_ c: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        let m = max(r, max(g, b))
        let scale: CGFloat = m < 0.85 ? 0.85 / max(m, 0.001) : 1
        return UIColor(
            red:   min(1, r * scale),
            green: min(1, g * scale),
            blue:  min(1, b * scale),
            alpha: 1
        )
    }

    // MARK: Two-stop gradient pair

    /// `(base, deep)` gradient pair for card / hero fills, from the mood tokens.
    ///
    /// `base` is the brightened palette colour; `deep` is a 20 % darkened variant suitable
    /// for the trailing stop in a top-leading → bottom-trailing gradient. Mood keys the
    /// palette dropped (`moodAcoustic`, `moodElectronic`) fall back to neutral.
    static func gradient(for moodKey: String) -> (Color, Color) {
        let entry = mapColors[paletteKey(forAxis: moodKey)] ?? mapColors["neutral"]!
        let raw = UIColor(
            red:   CGFloat(entry.r / 255),
            green: CGFloat(entry.g / 255),
            blue:  CGFloat(entry.b / 255),
            alpha: 1
        )
        let bright = brighten(raw)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        bright.getRed(&r, green: &g, blue: &b, alpha: &a)
        let s: CGFloat = 0.80
        let deep = UIColor(red: r * s, green: g * s, blue: b * s, alpha: 1)
        return (Color(uiColor: bright), Color(uiColor: deep))
    }
}
