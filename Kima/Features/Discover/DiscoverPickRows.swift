import SwiftUI

// MARK: - DiscoverFeaturedRow
//
// The next couple of picks after the featured hero card, cover-forward but scaled down. With DiscoverFeaturedPick
// and DiscoverCrateRow this steps the crate down in size: hero, featured, dense tail.

struct DiscoverFeaturedRow: View {
    let track: DiscoverTrack
    /// 1-based setlist index, continuing the count from the featured pick (which is 01).
    let index: Int
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let onPlay: () -> Void
    let onTogglePlay: () -> Void
    let onLike: () -> Void

    @Environment(AppEnvironment.self) private var env

    private func handleTap() {
        if isCurrentTrack { onTogglePlay() } else { onPlay() }
    }

    var body: some View {
        HStack(alignment: .center, spacing: KimaSpacing.md) {
            Text(String(format: "%02d", index))
                .font(KimaType.body)
                .monospacedDigit()
                .foregroundStyle(isCurrentTrack ? env.accent.color : KimaColor.textMuted)
                .frame(width: 24, alignment: .leading)

            ZStack {
                CoverArtImage(
                    coverId: track.coverUrl,
                    size: 256,
                    cornerRadius: KimaRadius.image,
                    accessibilityLabel: "\(track.title) — \(track.artist)"
                )
                .frame(width: 72, height: 72)
                .kimaSleeveElevation(cornerRadius: KimaRadius.image)
                .overlay(
                    RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                        .strokeBorder(KimaColor.hairline, lineWidth: 1)
                )

                if isCurrentTrack {
                    Circle().fill(KimaColor.discGlass).frame(width: 30, height: 30)
                    DiscoverPlayGlyph(isPlaying: isPlaying)
                }
            }

            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(track.title.lowercased())
                    .font(KimaType.bodyStrong)
                    .foregroundStyle(isCurrentTrack ? env.accent.color : KimaColor.textPrimary)
                    .lineLimit(1)
                HStack(spacing: KimaSpacing.sm) {
                    DiscoverTierIndicator(tier: track.tier)
                    Text(track.artist.lowercased())
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.duration.durationFormatted)
                .font(KimaType.caption)
                .monospacedDigit()
                .foregroundStyle(KimaColor.textMuted)

            DiscoverLikeButton(isLiked: track.isLiked, action: onLike)
        }
        .padding(.vertical, KimaSpacing.sm)
        .padding(.horizontal, KimaSpacing.lg)
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
    }
}

// MARK: - DiscoverCrateRow
//
// The dense tail of the crate: every pick after the featured handful. Roomy rows (48pt cover) with the match tier
// shown as a quiet dot instead of a capsule badge.

struct DiscoverCrateRow: View {
    let track: DiscoverTrack
    let index: Int
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let onPlay: () -> Void
    let onTogglePlay: () -> Void
    let onLike: () -> Void

    @Environment(AppEnvironment.self) private var env

    private func handleTap() {
        if isCurrentTrack { onTogglePlay() } else { onPlay() }
    }

    var body: some View {
        HStack(spacing: KimaSpacing.md) {
            Button(action: handleTap) {
                ZStack {
                    if isCurrentTrack {
                        DiscoverPlayGlyph(isPlaying: isPlaying)
                    } else {
                        Text(String(format: "%02d", index))
                            .font(KimaType.caption)
                            .monospacedDigit()
                            .foregroundStyle(KimaColor.textMuted)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            CoverArtImage(
                coverId: track.coverUrl,
                size: 96,
                cornerRadius: KimaRadius.image,
                accessibilityLabel: "\(track.title) — \(track.artist)"
            )
            .frame(width: 48, height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                    .strokeBorder(KimaColor.hairline, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(track.title.lowercased())
                    .font(KimaType.headline)
                    .foregroundStyle(isCurrentTrack ? env.accent.color : KimaColor.textPrimary)
                    .lineLimit(1)
                Text(track.artist.lowercased())
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DiscoverTierIndicator(tier: track.tier, compact: true)

            Text(track.duration.durationFormatted)
                .font(KimaType.caption)
                .monospacedDigit()
                .foregroundStyle(KimaColor.textMuted)
                .frame(minWidth: 34, alignment: .trailing)

            DiscoverLikeButton(isLiked: track.isLiked, action: onLike)
        }
        .padding(.vertical, KimaSpacing.md)
        .padding(.horizontal, KimaSpacing.lg)
        .background(isCurrentTrack ? KimaColor.surface : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
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
