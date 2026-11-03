import SwiftUI

// MARK: - KimaMarkStyle

/// Fill treatments for the Kima mark. The app shows `.drift`; the design lab previews all three and the
/// cover-art placeholder uses a still `.shiny`.
enum KimaMarkStyle {
    case shiny        // chrome / searchlight shimmer
    case holographic  // slow oil-slick spin
    case drift        // top-to-bottom spectrum with a slow hue sway
}

// MARK: - KimaMark

/// The Kima waveform mark, filled with the living spectrum. It is `.drift` unless an explicit `style` is
/// passed (design lab previews, the cover placeholder). `living` animates the sheen via
/// `TimelineView(.animation)`; pass `living: false` for a static fill in tiny/incidental spots.
struct KimaMark: View {
    var style: KimaMarkStyle = .drift
    /// Animate the spectrum. Default true.
    var living: Bool = true
    /// Holds the animation on its current frame, for a mark under a page that covers it.
    var paused: Bool = false

    private let holo  = Gradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red])
    // Drift spectrum — AMBER/GOLD crown on top, cooler colors beneath (rose → violet → blue → azure)
    // so the living mark reads amber-first and sits with the main app, then fans into the spectrum.
    private let driftSpectrum = Gradient(colors: [
        KimaColor.brand,                                   // brand amber SSOT (#c98f3f) (crown)
        Color(red: 255/255, green: 205/255, blue: 92/255),   // warm gold
        Color(red: 236/255, green: 72/255,  blue: 153/255),  // rose
        Color(red: 142/255, green: 38/255,  blue: 214/255),  // violet
        Color(red: 24/255,  green: 66/255,  blue: 222/255),  // deep blue
        Color(red: 0,       green: 150/255, blue: 200/255),  // azure
    ])
    // Deep spectrum (matches the app icon): richer rose/azure/blue/violet/amber around the white
    // searchlights so the mark holds its color at small sizes instead of washing to pastel.
    private let shiny = Gradient(colors: [
        Color(red: 224/255, green: 18/255,  blue: 92/255),   // deep rose
        .white,                                              // searchlight
        Color(red: 0,       green: 150/255, blue: 200/255),  // deep azure
        Color(red: 24/255,  green: 66/255,  blue: 222/255),  // deep blue
        .white,                                              // searchlight
        Color(red: 142/255, green: 38/255,  blue: 214/255),  // deep violet
        Color(red: 228/255, green: 104/255, blue: 0),        // deep amber
        .white,                                              // searchlight
        Color(red: 224/255, green: 18/255,  blue: 92/255),   // deep rose (seamless loop)
    ])

    /// On screen. A page pushed over the mark hides it without removing it; its animation stops while hidden, since a
    /// hidden one still costs the page on top dropped frames.
    @State private var onScreen = false

    var body: some View {
        if living {
            TimelineView(.animation(paused: paused || !onScreen)) { timeline in
                fill(style, at: timeline.date.timeIntervalSinceReferenceDate)
            }
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
        } else {
            fill(style, at: 0)
        }
    }

    @ViewBuilder
    private func fill(_ s: KimaMarkStyle, at t: TimeInterval) -> some View {
        let logo = Image("KimaLogo").renderingMode(.template).resizable().scaledToFit()
        switch s {
        case .holographic:
            let deg = t.truncatingRemainder(dividingBy: 18) / 18 * 360   // 18s spin
            logo.foregroundStyle(AngularGradient(gradient: holo, center: .center,
                                                 startAngle: .degrees(deg), endAngle: .degrees(deg + 360)))
        case .shiny:
            let deg = t.truncatingRemainder(dividingBy: 8) / 8 * 360      // 8s shimmer
            logo.foregroundStyle(AngularGradient(gradient: shiny, center: .center,
                                                 startAngle: .degrees(deg), endAngle: .degrees(deg + 360)))
        case .drift:
            // Amber crown stays put: a gentle ±14° hue breathing (≈16s sine) instead of a full
            // 360° spin, so the mark shimmers with life but never rotates off amber-on-top.
            let osc = sin(t * (2 * .pi / 16))                              // −1…1, ~16s period
            logo.foregroundStyle(LinearGradient(gradient: driftSpectrum,
                                                startPoint: .top, endPoint: .bottom))
                .hueRotation(.degrees(osc * 14))
        }
    }
}
