import SwiftUI

// MARK: - PlayerProgressStrip

/// Progress strip shared by MiniPlayerBar and MiniPlayerEdgeTab. Reads `currentTime` and `duration` from
/// `PlaybackController` and fills with the adaptive accent so it crossfades on track change. `height` sets each
/// surface's strip weight.
struct PlayerProgressStrip: View {

    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env

    /// Strip height in points.  Default: 2 pt.
    var height: CGFloat = 2

    /// The fill is scaled, not re-measured, so a time tick never triggers a layout pass.
    var body: some View {
        let ratio = player.duration > 0
            ? min(1, max(0, player.currentTime / player.duration))
            : 0.0
        ZStack(alignment: .leading) {
            Rectangle().fill(KimaColor.hairline)
            Rectangle()
                .fill(env.accent.color)
                .scaleEffect(x: ratio, y: 1, anchor: .leading)
                .animation(.linear(duration: 0.5), value: ratio)
        }
        .frame(height: height)
    }
}

// MARK: - AlbumSleeveThumbnail

/// Shared album-sleeve cover thumbnail for mini-player surfaces: `CoverArtImage` at `size x 2`,
/// rounded continuous clip (default `KimaRadius.image`; callers pass ladder tokens), drop shadow,
/// 0.5 pt hairline, and a cross-fade keyed to `animationId` (pass the track id).
struct AlbumSleeveThumbnail: View {

    let coverId: String?
    /// Pre-resolved image URL that bypasses `coverId` (long-form art). Default nil = music path.
    var directURL: URL? = nil
    /// Display frame size in points.  Image request size = `size × 2` for @2x.
    let size: CGFloat
    var cornerRadius: CGFloat     = KimaRadius.image
    var shadowRadius: CGFloat     = 6
    var shadowOpacity: Double     = 0.45
    var shadowY: CGFloat          = 3
    /// Optional animation key: the thumbnail cross-fades when this value changes.
    var animationId: AnyHashable? = nil

    var body: some View {
        CoverArtImage(
            coverId: coverId,
            directURL: directURL,
            size: Int(size) * 2,           // @2x quality request
            cornerRadius: cornerRadius
        )
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Sleeve shadow — art floats off the surface like a real album.
        .kimaShapeShadow(cornerRadius: cornerRadius, opacity: shadowOpacity, radius: shadowRadius, y: shadowY)
        // Hairline frame — sleeve-edge treatment; invisible on dark backgrounds,
        // grounds the card as a discrete object against light cover art edges.
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(KimaColor.hairline, lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.3), value: animationId)
    }
}

// MARK: - PlayerVibeMatchBadge

/// Colour-coded match badge below the artist name in the full player.
///   ≥ 80 % → positive (green)  — strong match
///   ≥ 60 % → caution  (amber)  — medium match / heads-up
///   < 60 % → textMuted         — low confidence, quiet treatment
struct PlayerVibeMatchBadge: View {
    let score: Int

    var body: some View {
        let (fg, bg): (Color, Color) = score >= 80
            ? (KimaColor.positive,                  KimaColor.positive.opacity(0.18))
            : score >= 60
            ? (KimaColor.caution,                   KimaColor.caution.opacity(0.18))
            : (KimaColor.textMuted,                 KimaColor.textMuted.opacity(0.10))

        HStack(spacing: KimaSpacing.xs) {
            Image(systemName: "waveform")
                .font(.system(size: 9, weight: .bold))
            Text("\(score)% match")
                .font(KimaType.meta)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, KimaSpacing.sm)
        .padding(.vertical, KimaSpacing.xs)
        .background(bg, in: Capsule())
    }
}
