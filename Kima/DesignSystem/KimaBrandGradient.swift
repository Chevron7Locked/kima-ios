import SwiftUI
import UIKit

/// The Kima logo's gradient: amber at the top through rose and violet to azure. The vibe map gives every track a
/// `colour` between 0 and 1 (0 the azure end, 1 the amber end) and this turns it into a screen colour.
///
/// Blends neighbouring stops per channel in plain sRGB (not linear light), rounding each channel, as the web does.
enum KimaBrandGradient {

    /// (position down the logo, 0 = top, hex colour), same 14 stops as the web.
    static let stops: [(position: Double, hex: UInt32)] = [
        (0.02, 0xfca506), (0.09, 0xfdac15), (0.17, 0xfdb530), (0.24, 0xfcb253), (0.31, 0xf69472),
        (0.39, 0xe86690), (0.46, 0xcd45aa), (0.54, 0xa633c2), (0.61, 0x7731d2), (0.69, 0x483ad9),
        (0.76, 0x234ed9), (0.83, 0x0e6bd3), (0.91, 0x0583cd), (0.98, 0x0191c9),
    ]

    /// RGB (0...255) at `share` along the gradient: 0 the azure end, 1 the amber end.
    /// Values outside 0...1 are clamped.
    static func rgb(at share: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        let t = 1 - min(1, max(0, share))
        let first = stops[0], last = stops[stops.count - 1]
        if t <= first.position { return channels(first.hex) }
        if t >= last.position { return channels(last.hex) }
        for i in 1..<stops.count where t <= stops[i].position {
            let (p0, h0) = stops[i - 1]
            let (p1, h1) = stops[i]
            let f = (t - p0) / (p1 - p0)
            let a = channels(h0), b = channels(h1)
            func mix(_ x: UInt8, _ y: UInt8) -> UInt8 {
                UInt8(max(0, min(255, (Double(x) + (Double(y) - Double(x)) * f).rounded())))
            }
            return (mix(a.r, b.r), mix(a.g, b.g), mix(a.b, b.b))
        }
        return channels(last.hex)
    }

    /// The colour at `share` as 0xRRGGBB.
    static func hex(at share: Double) -> UInt32 {
        let c = rgb(at: share)
        return UInt32(c.r) << 16 | UInt32(c.g) << 8 | UInt32(c.b)
    }

    static func uiColor(at share: Double) -> UIColor {
        let c = rgb(at: share)
        return UIColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }

    static func color(at share: Double) -> Color {
        Color(uiColor: uiColor(at: share))
    }

    private static func channels(_ hex: UInt32) -> (r: UInt8, g: UInt8, b: UInt8) {
        (UInt8((hex >> 16) & 0xff), UInt8((hex >> 8) & 0xff), UInt8(hex & 0xff))
    }
}
