import SwiftUI

// MARK: - PreviewBadge

/// "preview" tag for tracks the user does not own: the neutral `KimaTag`. While a preview is
/// playing it reads "▶ preview" in `activeColor` on a faint tint of it. One badge for the artist
/// top tracks, album rows and browse-playlist rows.
struct PreviewBadge: View {
    var isActive = false
    var activeColor: Color = KimaColor.brand

    var body: some View {
        if isActive {
            Text("▶ preview")
                .font(KimaType.meta)
                .foregroundStyle(activeColor)
                .padding(.horizontal, KimaSpacing.sm)
                .padding(.vertical, KimaSpacing.xs)
                .background(activeColor.opacity(0.15), in: Capsule())
                .fixedSize()
        } else {
            KimaTag(text: "preview")
        }
    }
}
