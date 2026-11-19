import SwiftUI

/// A detail page's one amber control: a 48pt play/pause disc with a dark glyph (album, artist, playlist, podcast,
/// shared track).
struct KimaHeroPlayButton: View {
    var isAudible = false
    var label: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(KimaColor.brand)
                Image(systemName: isAudible ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(KimaColor.onBrand)
                    .offset(x: isAudible ? 0 : 1)
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? (isAudible ? "pause" : "play"))
        // Stable test hook ("hero-play"): a detail page's one amber control; pages hold at most one.
        .accessibilityIdentifier("hero-play")
    }
}
