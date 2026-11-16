import SwiftUI

// MARK: - DiscoverFeaturedPick
// The week's best recommendation (`DiscoverPlaylist.featuredPick`) as a large cover-forward card. The backdrop
// glow comes from the pick's own cover (`CoverArtColor.palette`), resting violet while loading. When this track
// is active, the title and play glyph use `env.accent.color`.

struct DiscoverFeaturedPick: View {
    let track: DiscoverTrack
    /// How this track's control reads (engine truth scoped by identity, ADR 0001) — the one
    /// derived value behind the glyph, the tint, and what a tap honors.
    let displayState: RowDisplayState
    let onPlay: () -> Void
    let onTogglePlay: () -> Void
    let onLike: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var palette: CoverArtPalette?

    /// This track holds the playback session — the dispatch question (ADR 0001).
    private var isCurrent: Bool { displayState != .none }

    private func handleTap() {
        if isCurrent { onTogglePlay() } else { onPlay() }
    }

    private var glowTop: Color { palette?.vibrant     ?? KimaColor.ambient }
    private var glowLow: Color { palette?.darkVibrant ?? KimaColor.surfaceRaised }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.lg) {
            kicker

            HStack(alignment: .top, spacing: KimaSpacing.lg) {
                cover
                meta
            }
        }
        .kimaPaletteWashCard(tint: glowTop)
        .padding(.horizontal, KimaSpacing.lg)
        .task(id: track.coverUrl) {
            palette = await CoverArtColor.palette(coverId: track.coverUrl, server: env.server)
        }
    }

    // MARK: Kicker

    private var kicker: some View {
        HStack(spacing: KimaSpacing.sm) {
            KimaKicker(title: "this week's pick")
            Spacer(minLength: 0)
            DiscoverTierIndicator(tier: track.tier)
        }
    }

    // MARK: Cover + glow

    private var cover: some View {
        Button(action: handleTap) {
            CoverArtImage(
                coverId: track.coverUrl,
                size: 512,
                cornerRadius: KimaRadius.image,
                accessibilityLabel: "\(track.title) — \(track.artist)"
            )
            .frame(width: 112, height: 112)
            // The tile sits under the glow and shadow: a drop shadow reads only the opaque
            // silhouette, which an inset hairline doesn't change, so this reorder lands in old pixels.
            .kimaArtworkTile()
            // Glow lives in the background so it bleeds behind the art as a soft halo
            // without enlarging the cover's layout footprint (no left-side dead space).
            .background {
                RadialGradient(
                    colors: [glowTop.opacity(0.35), glowLow.opacity(0.12), .clear],
                    center: .center, startRadius: 4, endRadius: 92
                )
                .frame(width: 150, height: 150)
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.5), radius: 18, x: 0, y: 8)
            .overlay(alignment: .bottomTrailing) { playGlyph.padding(KimaSpacing.sm) }
        }
        .buttonStyle(.plain)
    }

    private var playGlyph: some View {
        ZStack {
            Circle().fill(KimaColor.discGlass).frame(width: 34, height: 34)
            DiscoverPlayGlyph(isPlaying: displayState == .playing,
                              playColor: isCurrent ? nil : KimaColor.textPrimary, playWeight: .semibold)
        }
        .allowsHitTesting(false)
    }

    // MARK: Meta

    private var meta: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            Text(track.title.lowercased())
                .font(KimaType.headline)
                .foregroundStyle(isCurrent ? env.accent.color : KimaColor.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(track.artist.lowercased()) · \(track.album.lowercased())")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
                .lineLimit(2)

            Text(track.duration.durationFormatted)
                .font(KimaType.meta)
                .monospacedDigit()
                .foregroundStyle(KimaColor.textMuted)

            Spacer(minLength: KimaSpacing.sm)

            HStack(spacing: KimaSpacing.md) {
                let audible = displayState == .playing
                KimaPrimaryButton(title: audible ? "pause" : "play",
                                  systemImage: audible ? "pause.fill" : "play.fill",
                                  size: .compact, action: handleTap)

                Button(action: onLike) {
                    Image(systemName: track.isLiked ? "heart.fill" : "heart").symbolEffect(.bounce, value: track.isLiked)
                        .font(.system(size: 17))
                        .foregroundStyle(track.isLiked ? KimaColor.textPrimary : KimaColor.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(track.isLiked ? "unlike" : "like")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
