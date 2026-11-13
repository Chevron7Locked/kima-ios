import SwiftUI

// MARK: - DiscoverRowDispatch
//
// What every Discover track row shares: the inputs and the dispatch decision (ADR 0001).
// The rows differ only in layout; this is the shape they all carry.

struct DiscoverRowDispatch {
    let track: DiscoverTrack
    /// 1-based setlist index, continuing the count from the featured pick (which is 01).
    let index: Int
    /// How this track's control reads (engine truth scoped by identity, ADR 0001) — the one
    /// derived value behind the glyph, the tint, and what a tap honors.
    let displayState: RowDisplayState
    let onPlay: () -> Void
    let onTogglePlay: () -> Void
    let onLike: () -> Void

    /// This track holds the playback session — the dispatch question (ADR 0001).
    var isCurrent: Bool { displayState != .none }

    func handleTap() {
        if isCurrent { onTogglePlay() } else { onPlay() }
    }
}

// MARK: - DiscoverFeaturedRow
//
// The next couple of picks after the featured hero card, cover-forward but scaled down. With DiscoverFeaturedPick
// and DiscoverCrateRow this steps the crate down in size: hero, featured, dense tail.

struct DiscoverFeaturedRow: View {
    let row: DiscoverRowDispatch

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(alignment: .center, spacing: KimaSpacing.md) {
            Text(String(format: "%02d", row.index))
                .font(KimaType.body)
                .monospacedDigit()
                .foregroundStyle(row.isCurrent ? env.accent.color : KimaColor.textMuted)
                .frame(width: 24, alignment: .leading)

            ZStack {
                CoverArtImage(
                    coverId: row.track.coverUrl,
                    size: 256,
                    cornerRadius: KimaRadius.image,
                    accessibilityLabel: "\(row.track.title) — \(row.track.artist)"
                )
                .frame(width: 72, height: 72)
                .kimaSleeveElevation(cornerRadius: KimaRadius.image)
                .overlay(
                    RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                        .strokeBorder(KimaColor.hairline, lineWidth: 1)
                )

                if row.isCurrent {
                    Circle().fill(KimaColor.discGlass).frame(width: 30, height: 30)
                    DiscoverPlayGlyph(isPlaying: row.displayState == .playing)
                }
            }

            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(row.track.title.lowercased())
                    .font(KimaType.bodyStrong)
                    .foregroundStyle(row.isCurrent ? env.accent.color : KimaColor.textPrimary)
                    .lineLimit(1)
                HStack(spacing: KimaSpacing.sm) {
                    DiscoverTierIndicator(tier: row.track.tier)
                    Text(row.track.artist.lowercased())
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.track.duration.durationFormatted)
                .font(KimaType.caption)
                .monospacedDigit()
                .foregroundStyle(KimaColor.textMuted)

            DiscoverLikeButton(isLiked: row.track.isLiked, action: row.onLike)
        }
        .padding(.vertical, KimaSpacing.sm)
        .padding(.horizontal, KimaSpacing.lg)
        .contentShape(Rectangle())
        .onTapGesture { row.handleTap() }
    }
}

// MARK: - DiscoverCrateRow
//
// The dense tail of the crate: every pick after the featured handful. Roomy rows (48pt cover) with the match tier
// shown as a quiet dot instead of a capsule badge.

struct DiscoverCrateRow: View {
    let row: DiscoverRowDispatch

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: KimaSpacing.md) {
            Button(action: row.handleTap) {
                ZStack {
                    if row.isCurrent {
                        DiscoverPlayGlyph(isPlaying: row.displayState == .playing)
                    } else {
                        Text(String(format: "%02d", row.index))
                            .font(KimaType.caption)
                            .monospacedDigit()
                            .foregroundStyle(KimaColor.textMuted)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            CoverArtImage(
                coverId: row.track.coverUrl,
                size: 96,
                cornerRadius: KimaRadius.image,
                accessibilityLabel: "\(row.track.title) — \(row.track.artist)"
            )
            .frame(width: 48, height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                    .strokeBorder(KimaColor.hairline, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(row.track.title.lowercased())
                    .font(KimaType.headline)
                    .foregroundStyle(row.isCurrent ? env.accent.color : KimaColor.textPrimary)
                    .lineLimit(1)
                Text(row.track.artist.lowercased())
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DiscoverTierIndicator(tier: row.track.tier, compact: true)

            Text(row.track.duration.durationFormatted)
                .font(KimaType.caption)
                .monospacedDigit()
                .foregroundStyle(KimaColor.textMuted)
                .frame(minWidth: 34, alignment: .trailing)

            DiscoverLikeButton(isLiked: row.track.isLiked, action: row.onLike)
        }
        .padding(.vertical, KimaSpacing.md)
        .padding(.horizontal, KimaSpacing.lg)
        .background(row.isCurrent ? KimaColor.surface : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { row.handleTap() }
    }
}

/// The heart button at the end of a Discover track row.
private struct DiscoverLikeButton: View {
    let isLiked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isLiked ? "heart.fill" : "heart").symbolEffect(.bounce, value: isLiked)
                .font(.system(size: 15))
                .foregroundStyle(isLiked ? KimaColor.textPrimary : KimaColor.textMuted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLiked ? "unlike" : "like")
    }
}

// MARK: - DiscoverPlayGlyph

/// A pick's play state: a moving waveform while it plays, else a play triangle (accent colour unless `playColor` is given).
struct DiscoverPlayGlyph: View {
    let isPlaying: Bool
    var playColor: Color? = nil
    var playWeight: Font.Weight = .regular

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if isPlaying {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(env.accent.color)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers)
        } else {
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: playWeight))
                .foregroundStyle(playColor ?? env.accent.color)
        }
    }
}
