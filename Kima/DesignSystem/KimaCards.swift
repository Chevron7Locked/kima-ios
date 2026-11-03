import SwiftUI

// MARK: - Duration formatting

extension Double {
    /// Formats a duration in seconds as `m:ss` (under one hour) or `h:mm:ss`, rounded to the
    /// nearest second. Negative, NaN and infinite values read as "0:00".
    /// Suitable for tabular display in track lists; keep the font monospaced at the call site.
    var durationFormatted: String {
        guard isFinite, self > 0 else { return "0:00" }
        let total = self >= 1e9 ? 1_000_000_000 : Int(self.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Length of a book or an episode in words a clock can't be mistaken for: "12h 34m", "45m", "<1m".
    var lengthLabel: String {
        guard isFinite, self > 0 else { return "<1m" }
        let total = Int(self.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }
}

// MARK: - CoverPlayBadge

/// Small "play" badge on a cover-art card's corner: a dark-glass disc with a light glyph; the playing tile (`isActive`)
/// shows the amber disc; a tile whose playback is being fetched (`isBusy`) shows the amber disc with a spinner and
/// ignores taps. 36pt drawn, 44pt tappable. Place inside a `ZStack(alignment: .bottomTrailing)` over the
/// cover art; the caller supplies corner padding.
struct CoverPlayBadge: View {
    var isActive: Bool = false
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isActive || isBusy {
                    Circle().fill(KimaColor.brand)
                } else {
                    Circle()
                        .fill(KimaColor.discGlass)
                        .overlay(Circle().strokeBorder(KimaColor.hairline, lineWidth: 1))
                }
                if isBusy {
                    ProgressView()
                        .tint(KimaColor.onBrand)
                        .scaleEffect(0.8)
                        .accessibilityIdentifier("play-badge-loading")
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? KimaColor.onBrand : KimaColor.textPrimary)
                        .offset(x: 1)
                }
            }
            .frame(width: 36, height: 36)
            // Tappable across 44pt without changing the layout: the disc's size is fixed, so the margin is too.
            .padding((KimaLayout.minTouchTarget - 36) / 2)
            .contentShape(Rectangle())
            .padding(-(KimaLayout.minTouchTarget - 36) / 2)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityIdentifier("play-badge")
        .accessibilityLabel(isBusy ? "loading" : "play")
    }
}
