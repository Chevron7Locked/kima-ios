import SwiftUI

// MARK: - VibeHeroStarField

/// A night sky for Home's vibe map card: 18 twinkling stars, ~110 fainter ones (mostly tiny and dim) and Orion from
/// its real star positions, no figure lines. Stars over the text band are dimmed for contrast; a fixed seed keeps the
/// sky the same every launch. A 10 fps timeline drives the twinkle; Reduce Motion, Low Power Mode or the app in the
/// background draw one still frame.
struct VibeHeroStarField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Star {
        let x: Double, y: Double
        let radius: CGFloat
        let opacity: Double
        let phase: Double, speed: Double
        var tint: Color = KimaColor.textPrimary
    }

    /// The field: brightness follows a steep curve, so faint stars far outnumber bright ones, as in a real sky.
    static let field: [Star] = {
        var rng = HeroStarRNG(seed: 0x4E49_4748_545F_534B)
        var out: [Star] = (0..<110).map { _ in
            let u = rng.nextUnit()
            let b = pow(u, 3.2)                      // 0…1, mostly near 0
            return Star(x: rng.nextUnit(), y: rng.nextUnit(),
                        radius: CGFloat(0.35 + b * 1.05), opacity: 0.12 + b * 0.6,
                        phase: rng.nextUnit() * 6.2832, speed: 0.3 + rng.nextUnit() * 0.9)
        }
        // The card's own 18 stars, in their long-standing places.
        var old = HeroStarRNG(seed: 0x5641_4245_5F53_5441)
        for _ in 0..<18 {
            let x = old.nextUnit(), y = 0.06 + old.nextUnit() * 0.42
            let r = CGFloat(0.6 + old.nextUnit() * 1.3), o = 0.22 + old.nextUnit() * 0.55
            let p = old.nextUnit() * 6.2832, s = 0.45 + old.nextUnit() * 1.05
            _ = (old.nextUnit(), old.nextUnit(), old.nextUnit())   // the old drift values: kept so the 18 keep their places
            out.append(Star(x: x, y: y, radius: r * 0.8, opacity: o, phase: p, speed: s))
        }
        return out
    }()

    /// Orion's main stars from their real right ascension / declination (J2000) and visual magnitude.
    /// Projected flat around the belt: east to the left (as seen from the ground), north up.
    private static let orionCatalog: [(name: String, raHours: Double, dec: Double, mag: Double)] = [
        ("betelgeuse", 5.9195, 7.407, 0.50), ("bellatrix", 5.4189, 6.350, 1.64), ("meissa", 5.5856, 9.934, 3.39),
        ("alnitak", 5.6793, -1.943, 1.77), ("alnilam", 5.6036, -1.202, 1.69), ("mintaka", 5.5334, -0.299, 2.23),
        ("saiph", 5.7959, -9.670, 2.09), ("rigel", 5.2423, -8.202, 0.13),
        ("iota", 5.5906, -5.910, 2.77), ("theta", 5.5881, -5.390, 4.0),
    ]

    /// Orion's stars in card units, given the card size (so the figure keeps its true shape).
    static func orionStars(in size: CGSize) -> [String: (CGPoint, Star)] {
        let ptPerDeg = size.height * 0.60 / 20.0          // Meissa → Saiph (~19.6°) spans ~60% of the card height
        let centre = CGPoint(x: size.width * 0.80, y: size.height * 0.36)
        var out: [String: (CGPoint, Star)] = [:]
        for (i, s) in orionCatalog.enumerated() {
            let dx = -(s.raHours - 5.6036) * 15 * cos(s.dec * .pi / 180)   // east (higher RA) to the left
            let dy = -(s.dec - (-0.9))
            let p = CGPoint(x: centre.x + dx * ptPerDeg, y: centre.y + dy * ptPerDeg)
            var star = Star(x: 0, y: 0, radius: CGFloat(0.7 + (3.6 - s.mag) * 0.27),
                            opacity: min(0.95, 0.55 + (3.6 - s.mag) * 0.13),
                            phase: Double(i) * 1.7, speed: 0.35 + Double(i % 3) * 0.15)
            if s.name == "betelgeuse" { star.tint = Color(hex: 0xFFD7B5) }   // faint warm, not amber
            if s.name == "rigel" { star.tint = Color(hex: 0xDDE7FF) }        // faint blue-white
            out[s.name] = (p, star)
        }
        return out
    }

    @Environment(\.scenePhase) private var scenePhase
    /// Orion placed for the last card size, so a frame does not recompute it.
    @State private var orion: (size: CGSize, stars: [(CGPoint, Star)], box: CGRect)?

    /// Still when Reduce Motion or Low Power Mode is on, or the app is not in front.
    private var isStill: Bool {
        reduceMotion || scenePhase != .active || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        Group {
            if isStill {
                Canvas { ctx, size in draw(&ctx, size: size, t: nil) }
            } else {
                // The twinkle is slow (≤ 1.2 rad/s), so 10 frames a second look the same as more.
                TimelineView(.periodic(from: .now, by: 1.0 / 10.0)) { tl in
                    Canvas { ctx, size in draw(&ctx, size: size, t: tl.date.timeIntervalSinceReferenceDate) }
                }
            }
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { placeOrion(in: $0) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func placeOrion(in size: CGSize) {
        guard orion?.size != size, size.width > 0 else { return }
        let stars = Array(Self.orionStars(in: size).values)
        let box = stars.map { CGRect(origin: $0.0, size: .zero) }.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -6, dy: -6)
        orion = (size, stars, box)
    }

    /// Brightness at time `t`; a still frame (nil) shows every star at full brightness.
    private func twinkle(_ s: Star, _ t: Double?) -> Double {
        guard let t else { return 1 }
        return 0.78 + 0.22 * (0.5 + 0.5 * sin(t * s.speed + s.phase))
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double?) {
        let o = orion?.size == size ? orion : nil
        // Stars over the text band are dimmed so the label keeps its contrast.
        func textBand(_ p: CGPoint) -> Double { p.y > size.height * 0.55 ? 0.4 : 1.0 }
        for s in Self.field {
            let p = CGPoint(x: s.x * size.width, y: s.y * size.height)
            // Keep Orion's patch clear of faint field stars so the figure reads.
            if let o, o.box.contains(p) && s.radius < 1.1 { continue }
            let r = s.radius
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(s.tint.opacity(s.opacity * textBand(p) * twinkle(s, t))))
        }
        for (p, s) in o?.stars ?? [] {
            let r = s.radius
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.2 * r, y: p.y - 2.2 * r, width: 4.4 * r, height: 4.4 * r)),
                     with: .color(s.tint.opacity(0.07 * textBand(p))))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(s.tint.opacity(s.opacity * textBand(p) * twinkle(s, t))))
        }
    }
}

private struct HeroStarRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    private mutating func next() -> UInt64 { state ^= state << 13; state ^= state >> 7; state ^= state << 17; return state }
    mutating func nextUnit() -> Double { Double(next() % 10_000) / 10_000 }
}
