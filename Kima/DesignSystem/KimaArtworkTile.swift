import SwiftUI

// MARK: - Artwork tile

extension View {
    /// The app's most-repeated visual, named: artwork clipped to a continuous rounded rectangle
    /// with the shared 1pt hairline edge. Every rounded-rect cover, thumbnail and mosaic tile — and
    /// the drawn placeholders that stand in for missing art — uses this; call-site extras (elevation,
    /// play badges, now-playing overlays) stay outside it, above the tile. `cornerRadius` is
    /// `KimaRadius.image` for list and rail tiles; hero covers pass `KimaRadius.hero`. Circular
    /// avatars and the deliberate 0.5pt sleeve frame are their own treatments and keep their spelling.
    func kimaArtworkTile(cornerRadius: CGFloat = KimaRadius.image) -> some View {
        clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(KimaColor.hairline, lineWidth: 1)
            )
    }
}
