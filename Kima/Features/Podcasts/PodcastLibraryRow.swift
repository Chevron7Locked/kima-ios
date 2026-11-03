import SwiftUI

// MARK: - PodcastLibraryRow

/// Full-width row for a subscribed show in "My Podcasts": cover, title, author and an episode meta line.
/// Grayscale on purpose (spoken word carries no vibe accent). Row height is fixed by construction (fixed-frame cover +
/// reservesSpace on the two-line title), so async cover loads never reflow rows while scrolling.
struct PodcastLibraryRow: View {
    let podcast: Podcast
    let onTap: () -> Void

    private static let coverSize: CGFloat   = 80
    private static let coverRadius: CGFloat = KimaRadius.image

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: KimaSpacing.lg) {
                    // Lit cover — real sleeve shadow + top-lit edge (grayscale, no vibe accent).
                    CoverArtImage(
                        coverId: podcast.coverUrl,
                        size: 256,
                        cornerRadius: Self.coverRadius,
                        accessibilityLabel: "\(podcast.title) cover",
                        placeholderSymbol: "mic"
                    )
                    .frame(width: Self.coverSize, height: Self.coverSize)
                    .kimaSleeveElevation(cornerRadius: Self.coverRadius)

                    VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                        Text(podcast.title.lowercased())
                            .font(KimaType.headline)
                            .foregroundStyle(KimaColor.textPrimary)
                            .lineLimit(2, reservesSpace: true)   // fixes row height → no reflow

                        Text(podcast.author.lowercased())
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textSecondary)
                            .lineLimit(1)

                        metaLine
                    }

                    Spacer(minLength: KimaSpacing.sm)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KimaColor.textMuted)
                }
                .padding(.vertical, KimaSpacing.md)
                .padding(.horizontal, KimaSpacing.lg)

                // Inset liner-note hairline — starts under the text, aligning the cover as the
                // left anchor of the row. Editorial rule, not a bordered card.
                KimaHairline()
                    .padding(.leading, KimaSpacing.lg + Self.coverSize + KimaSpacing.lg)
                    .padding(.trailing, KimaSpacing.lg)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metadata line

    /// Mono setlist-voice metadata: episode count · latest episode date. Always exactly one
    /// line (keeps the row height stable); scales down slightly rather than wrapping on narrow
    /// devices. Latest date derives from `episodes.first` — the embedded list is newest-first
    /// (the detail VM treats `.reversed()` as "oldest").
    private var metaLine: some View {
        let count  = podcast.episodeCount ?? podcast.episodes.count
        let latest = podcast.episodes.first?.publishedAt.podcastDateDisplay
        return HStack(spacing: KimaSpacing.xs) {
            Text("\(count) episode\(count == 1 ? "" : "s")")
            if let latest {
                Text("·")
                Text("latest \(latest.lowercased())")
            }
        }
        .font(KimaType.meta.monospacedDigit())
        .foregroundStyle(KimaColor.textMuted)
        .lineLimit(1)
        .minimumScaleFactor(0.9)
    }
}
