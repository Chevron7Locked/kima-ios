import SwiftUI

// MARK: - DiscoverFeaturedPick
// The week's best recommendation (`DiscoverPlaylist.featuredPick`) as a large cover-forward card. The backdrop
// glow comes from the pick's own cover (`CoverArtColor.palette`), resting violet while loading. When this track
// is active, the title and play glyph use `env.accent.color`.

struct DiscoverFeaturedPick: View {
    /// The shared row shape (inputs + the one dispatch decision, ADR 0001) — the featured
    /// hero rides `DiscoverRowDispatch` like the rows below it, not its own copy.
    let row: DiscoverRowDispatch

    @Environment(AppEnvironment.self) private var env
    @State private var palette: CoverArtPalette?

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
        .task(id: row.track.coverUrl) {
            palette = await CoverArtColor.palette(coverId: row.track.coverUrl, server: env.server)
        }
    }

    // MARK: Kicker

    private var kicker: some View {
        HStack(spacing: KimaSpacing.sm) {
            KimaKicker(title: "this week's pick")
            Spacer(minLength: 0)
            DiscoverTierIndicator(tier: row.track.tier)
        }
    }

    // MARK: Cover + glow

    private var cover: some View {
        Button(action: row.handleTap) {
            CoverArtImage(
                coverId: row.track.coverUrl,
                size: 512,
                cornerRadius: KimaRadius.image,
                accessibilityLabel: "\(row.track.title) — \(row.track.artist)"
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
            DiscoverPlayGlyph(isPlaying: row.displayState == .playing,
                              playColor: row.isCurrent ? nil : KimaColor.textPrimary, playWeight: .semibold)
        }
        .allowsHitTesting(false)
    }

    // MARK: Meta

    private var meta: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            Text(row.track.title.lowercased())
                .font(KimaType.headline)
                .foregroundStyle(row.isCurrent ? env.accent.color : KimaColor.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(row.track.artist.lowercased()) · \(row.track.album.lowercased())")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
                .lineLimit(2)

            Text(row.track.duration.durationFormatted)
                .font(KimaType.meta)
                .monospacedDigit()
                .foregroundStyle(KimaColor.textMuted)

            Spacer(minLength: KimaSpacing.sm)

            HStack(spacing: KimaSpacing.md) {
                let audible = row.displayState == .playing
                KimaPrimaryButton(title: audible ? "pause" : "play",
                                  systemImage: audible ? "pause.fill" : "play.fill",
                                  size: .compact, action: row.handleTap)

                Button(action: row.onLike) {
                    Image(systemName: row.track.isLiked ? "heart.fill" : "heart").symbolEffect(.bounce, value: row.track.isLiked)
                        .font(.system(size: 17))
                        .foregroundStyle(row.track.isLiked ? KimaColor.textPrimary : KimaColor.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.track.isLiked ? "unlike" : "like")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
