import SwiftUI

// MARK: - DiscoverPodcastRow

/// Single row in the search-discover results list: cover thumbnail + title + author + Subscribe.
struct DiscoverPodcastRow: View {
    let result: DiscoverPodcastResult
    let isSubscribing: Bool
    let anySubscribing: Bool
    let onSubscribe: () -> Void

    var body: some View {
        HStack(spacing: KimaSpacing.md) {
            coverThumb

            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(result.name.lowercased())
                    .font(KimaType.bodyStrong)
                    .foregroundStyle(KimaColor.textPrimary)
                    .lineLimit(2)
                if !result.artist.isEmpty {
                    Text(result.artist.lowercased())
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                        .lineLimit(1)
                }
                if !result.canSubscribe {
                    Text("no RSS feed available")
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)
                }
            }

            Spacer(minLength: 0)

            if isSubscribing {
                ProgressView().tint(KimaColor.brand)
                    .frame(width: 80)
            } else {
                Button(action: onSubscribe) {
                    Text("subscribe")
                        .font(KimaType.captionStrong)
                        .foregroundStyle(result.canSubscribe ? KimaColor.base : KimaColor.textMuted)
                        .padding(.horizontal, KimaSpacing.md)
                        .padding(.vertical, KimaSpacing.sm)
                        .background(
                            result.canSubscribe ? KimaColor.brand : KimaColor.surface,
                            in: Capsule()
                        )
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!result.canSubscribe || anySubscribing)
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.sm)
    }

    // MARK: - Cover thumbnail

    private var coverThumb: some View {
        RemoteArtworkImage(urlString: result.coverUrl, placeholderSymbol: "mic", maxPixel: 156)
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous))
        // Shared soft lift so the search-result cover floats off the stage like every other cover
        // thumbnail (converges on the KimaCoverCard treatment — no bespoke shadow, no containment frame).
        .kimaSleeveElevation(cornerRadius: KimaRadius.image)
    }
}
