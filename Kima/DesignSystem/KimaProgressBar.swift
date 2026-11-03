import SwiftUI

/// Thin rounded progress bar shared by audiobook cards, the audiobook detail header,
/// the import job rows and the sync screen. Defaults to the quiet brand amber on a faint white track.
struct KimaProgressBar: View {
    /// Fraction 0–1; clamped — safe with any server value.
    let fraction: Double
    var height: CGFloat = 3
    var tint: Color = KimaColor.brand
    var track: Color = Color.white.opacity(0.18)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                    .frame(height: height)
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1), height: height)
            }
        }
        .frame(height: height)
    }
}
