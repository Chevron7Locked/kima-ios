import SwiftUI

// MARK: - ContinueListeningSection

/// Home section for recently played items ("Continue Listening"). The most recent item leads as a spotlight card:
/// full width over a smaller rail on compact width, two tiles wide at the head of one fitted rail on regular width.
/// Shown only when `!vm.recentlyListened.isEmpty`. See All goes to the Library tab (`onSeeAll`). A card opens its page
/// (`onItemTap`, resolved by the caller); its play badge plays it (`onItemPlay`).
struct ContinueListeningSection: View {
    let items: [RecentlyListenedItem]
    let onSeeAll: () -> Void
    /// Called with the tapped item; caller resolves `.type` to navigation destination.
    let onItemTap: (RecentlyListenedItem) -> Void
    /// Called from an item's play badge.
    let onItemPlay: (RecentlyListenedItem) -> Void
    /// Items whose play request is in flight: their badges spin and ignore repeat taps.
    var playingIds: Set<String> = []

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(
                title: "continue listening",
                onSeeAll: onSeeAll
            )

            if sizeClass == .regular {
                KimaRail(tileWidth: 148) { width in
                    if let first = items.first {
                        // Two tiles and the gap between them wide, its plate as tall as the tiles' covers. A hidden
                        // card underneath gives it a card's full height, so the rail keeps room for the tiles' text.
                        card(first, width: width)
                            .hidden()
                            .frame(width: 2 * width + KimaLayout.railGap, alignment: .leading)
                            .overlay(alignment: .top) {
                                spotlight(first, coverSize: width - 2 * KimaSpacing.md)
                                    .frame(height: width)
                            }
                    }
                    ForEach(items.dropFirst()) { item in card(item, width: width) }
                }
            } else {
                if let first = items.first {
                    spotlight(first)
                        .padding(.horizontal, KimaSpacing.lg)
                }

                let rest = Array(items.dropFirst())
                if !rest.isEmpty {
                    KimaRail {
                        ForEach(rest) { item in card(item, width: 120) }
                    }
                    .padding(.top, KimaSpacing.sm)
                }
            }
        }
    }

    private func spotlight(_ item: RecentlyListenedItem, coverSize: CGFloat = 116) -> some View {
        ContinueSpotlightCard(item: item, onTap: { onItemTap(item) }, onPlay: { onItemPlay(item) },
                              isBusy: playingIds.contains(item.id), coverSize: coverSize)
    }

    private func card(_ item: RecentlyListenedItem, width: CGFloat) -> some View {
        ContinueCard(item: item, onTap: { onItemTap(item) }, onPlay: { onItemPlay(item) },
                     cardWidth: width, isBusy: playingIds.contains(item.id))
    }
}

// MARK: - ContinueSpotlightCard

/// Full-width banner for the most recently played item: big cover art at the leading edge, a kicker ("resume"
/// with saved progress, else what the item is), title and subtitle on a top-lit plate, the play badge trailing.
/// The card opens the item's page; the badge plays it.
private struct ContinueSpotlightCard: View {
    let item: RecentlyListenedItem
    let onTap: () -> Void
    let onPlay: () -> Void
    /// The play request for this item is in flight: the badge spins and ignores repeat taps.
    var isBusy: Bool = false
    var coverSize: CGFloat = 116
    private let cornerRadius: CGFloat = KimaRadius.card

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: KimaSpacing.md) {
                CoverArtImage(coverId: item.coverId, size: 256, cornerRadius: KimaRadius.image, placeholderSymbol: item.placeholderSymbol)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: coverSize, height: coverSize)
                    .clipShape(RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous))
                    .kimaSleeveElevation(cornerRadius: KimaRadius.image)

                VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                    KimaKicker(title: item.hasPlaybackProgress ? "resume" : item.typeLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(item.displayTitle.lowercased())
                        .font(KimaType.headline)
                        .foregroundStyle(KimaColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    // Hero-scale subtitle: only MEANINGFUL text (an author name). The generic
                    // type label ("artist"/"album"/"podcast") reads as broken data at hero scale;
                    // the web shows it as a small chip and the rail cards below keep it.
                    if let sub = item.spotlightSubtitle {
                        Text(sub)
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: KimaSpacing.sm)

                // The badge's own label says "loading" while its fetch runs. These cards set an
                // explicit label naming the item, which replaces the merged text — so the busy
                // state has to be composed into this label, or a screen reader never hears it.
                CoverPlayBadge(isBusy: isBusy, action: onPlay)
                    .accessibilityLabel(
                        (isBusy ? "loading " : item.hasPlaybackProgress ? "resume " : "play ") + item.displayTitle)
            }
            .padding(KimaSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.kimaPlate, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .kimaSleeveElevation(cornerRadius: cornerRadius)
            .overlay(alignment: .bottom) {
                if item.hasPlaybackProgress, let pct = item.progress {
                    progressBar(pct: pct)
                }
            }
        }
        .buttonStyle(.kimaCard)
    }

    private func progressBar(pct: Double) -> some View {
        KimaProgressBar(fraction: pct / 100, track: Color.black.opacity(0.4))
            .padding(.horizontal, KimaSpacing.md)
        .padding(.bottom, KimaSpacing.sm)
    }
}
