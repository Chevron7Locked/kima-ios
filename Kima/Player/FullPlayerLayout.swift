import CoreGraphics

// MARK: - FullPlayerLayout

/// Sizes for the full player. iPhone and narrow windows: one column with the cover at most 340 pt. iPad
/// portrait: one centred column with a cover sized to the screen and a capped controls column. iPad landscape
/// (and wide, short windows): the cover on the left, the title, seek line, transport and volume on the right.
struct FullPlayerLayout: Equatable {
    /// Cover on the left, controls on the right.
    let sideBySide: Bool
    /// Largest side of the square cover (or the lyrics panel in its place).
    let artworkSide: CGFloat
    /// Width of the controls column: beside the cover, or under it on iPad portrait; 0 on iPhone.
    let controlsWidth: CGFloat

    static let phoneArtworkSide: CGFloat = 340
    /// Height the stacked layout needs under the cover: top bar, title, seek line, transport, volume, and the
    /// padding above the centred stack.
    static let stackedControlsHeight: CGFloat = 552
    /// Smallest cover on iPad portrait, so a short window still fits the controls under it.
    static let stackedArtworkMin: CGFloat = 240
    /// Height the side-by-side layout keeps clear of the cover: top bar and margins.
    static let sideBySideChromeHeight: CGFloat = 200
    /// Gap between the cover and the controls column.
    static let columnGap: CGFloat = 48
    /// Margin on each side of the iPad layouts.
    static let sideMargin: CGFloat = 48
    /// Widest the controls column under the cover gets on iPad portrait.
    static let stackedControlsMax: CGFloat = 620

    init(size: CGSize, isRegular: Bool) {
        guard isRegular, size.width >= 600 else {
            self.init(sideBySide: false, artworkSide: Self.phoneArtworkSide, controlsWidth: 0)
            return
        }
        let inner = size.width - 2 * Self.sideMargin
        if size.width > size.height, size.width >= 760 {
            let side = min(size.height - Self.sideBySideChromeHeight, size.width * 0.42, 620)
            let controls = min(460, inner - side - Self.columnGap)
            self.init(sideBySide: true, artworkSide: max(240, side), controlsWidth: controls)
        } else {
            let side = min(inner, size.height * 0.48, size.height - Self.stackedControlsHeight)
            self.init(sideBySide: false, artworkSide: max(Self.stackedArtworkMin, side),
                      controlsWidth: min(Self.stackedControlsMax, inner))
        }
    }

    init(sideBySide: Bool, artworkSide: CGFloat, controlsWidth: CGFloat) {
        self.sideBySide = sideBySide
        self.artworkSide = artworkSide
        self.controlsWidth = controlsWidth
    }
}
