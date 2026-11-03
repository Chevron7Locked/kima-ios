import SwiftUI

/// A detail page's one amber control: a 48pt play/pause disc with a dark glyph (album, artist, playlist, podcast,
/// shared track).
struct KimaHeroPlayButton: View {
    var isPlaying = false
    var label: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(KimaColor.brand)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(KimaColor.onBrand)
                    .offset(x: isPlaying ? 0 : 1)
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? (isPlaying ? "pause" : "play"))
    }
}
