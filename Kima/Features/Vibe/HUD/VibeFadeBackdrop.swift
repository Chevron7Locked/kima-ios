import SwiftUI

/// The light the readout, the panels and the search list sit on: the map darkens toward the base
/// colour with a soft violet glow, fading in from nothing over `fade` points on the side open to the
/// map, so the stars show through there. No edge, no box.
struct VibeFadeBackdrop: View {
    /// The side that opens onto the map: `.top` under the bottom stack, `.bottom` under the search list.
    var openEdge: VerticalEdge = .top
    var fade: CGFloat = 96

    var body: some View {
        GeometryReader { geo in
            let reach = min(fade / max(geo.size.height, 1), 1)
            ZStack {
                KimaColor.base.opacity(0.88)
                RadialGradient(colors: [KimaColor.ambient.opacity(0.34), .clear],
                               center: UnitPoint(x: 0.22, y: openEdge == .top ? 0.55 : 0.45),
                               startRadius: 4, endRadius: 300)
            }
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.85), location: reach),
                .init(color: .black, location: 1),
            ], startPoint: openEdge == .top ? .top : .bottom, endPoint: openEdge == .top ? .bottom : .top))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
