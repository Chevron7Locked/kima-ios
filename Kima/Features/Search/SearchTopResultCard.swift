import SwiftUI

// Extracted from SearchSectionViews.swift to keep that file under the ~350-line cap —
// the hero card grew a palette-driven glow (see below) and earned its own file.

// MARK: - Top Match card

/// Top match card: a library artist if one exists, otherwise the best external (Last.fm) music result.
/// Only library artists are tappable (discover artists have no library detail page on iOS).
/// The cover's palette (`CoverArtColor`) casts a soft glow and tints the card wash; it falls back to
/// resting violet while the palette loads or fails.
struct SearchTopResultCard: View {
    let libraryArtist:  Artist?
    let discoverArtist: DiscoverResult?
    /// Non-nil only when `libraryArtist` is present; nil for discover-only results.
    let onTap:          (() -> Void)?

    @Environment(AppEnvironment.self) private var env
    @State private var palette: CoverArtPalette?

    private var displayName: String {
        libraryArtist?.effectiveName ?? discoverArtist?.name ?? ""
    }
    private var coverId: String? {
        libraryArtist?.coverArt ?? libraryArtist?.image ?? discoverArtist?.image
    }
    private var sourceLabel: String {
        libraryArtist != nil ? "your library" : "discover"
    }
    private var subtitle: String? {
        if let count = libraryArtist?.albumCount {
            return "\(count) album\(count == 1 ? "" : "s")"
        }
        if let l = discoverArtist?.listeners, l > 0 {
            return "\(l / 1_000)K listeners"
        }
        return nil
    }
    private var glowTop: Color { palette?.vibrant     ?? KimaColor.ambient }
    private var glowLow: Color { palette?.darkVibrant ?? KimaColor.surfaceRaised }

    var body: some View {
        KimaSectionHeader(title: "top result")

        Group {
            if let tap = onTap {
                Button(action: tap) { cardContent }
                    .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.top, KimaSpacing.sm)
        .task(id: coverId) {
            palette = await CoverArtColor.palette(coverId: coverId, server: env.server)
        }
    }

    private var cardContent: some View {
        HStack(spacing: KimaSpacing.lg) {
            ZStack {
                RadialGradient(
                    colors: [glowTop.opacity(0.35), glowLow.opacity(0.12), .clear],
                    center: .center, startRadius: 4, endRadius: 76
                )
                .frame(width: 116, height: 116)
                .allowsHitTesting(false)

                CoverArtImage(
                    coverId: coverId,
                    size: 300,
                    cornerRadius: KimaRadius.image
                )
                .frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 6)
                .overlay(RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous).strokeBorder(KimaColor.hairline, lineWidth: 1))
            }
            .frame(width: 116, height: 116)

            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                HStack(spacing: KimaSpacing.xs) {
                    Text("artist")
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)
                        .tracking(0.1)
                    if libraryArtist == nil {
                        Text("· \(sourceLabel)")
                            .font(KimaType.meta)
                            .foregroundStyle(KimaColor.textMuted)
                            .tracking(0.1)
                    }
                }
                Text(displayName.lowercased())
                    .font(KimaType.headline)
                    .foregroundStyle(KimaColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let sub = subtitle {
                    Text(sub)
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                }
            }

            Spacer(minLength: 0)

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(KimaColor.textMuted)
            }
        }
        .kimaPaletteWashCard(tint: glowTop)
    }
}
