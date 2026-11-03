import SwiftUI

// MARK: - SeriesBookRow

/// One book in AudiobookSeriesView. The row opens the book's page; the play badge plays it from its
/// saved place.
struct SeriesBookRow: View {
    let book: Audiobook
    let sequenceNumber: Int
    let onPlay: () -> Void

    @Environment(AppEnvironment.self) private var env

    // MARK: Now-playing awareness (visual only)

    private var isThisBookLoaded: Bool { env.player.isAudiobookLoaded(book.id) }
    private var isThisBookPlaying: Bool { isThisBookLoaded && env.player.isPlaying }

    private var progressLabel: String? {
        guard let p = book.progress else { return nil }
        if p.isFinished { return "finished" }
        let pct = Int(p.progress.rounded())
        return pct > 0 ? "\(pct)%" : nil
    }

    private var progressColor: Color {
        book.progress?.isFinished == true ? KimaColor.positive : KimaColor.caution
    }

    var body: some View {
        HStack(spacing: 0) {
            NavigationLink {
                AudiobookDetailView(id: book.id)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)

            CoverPlayBadge(isActive: isThisBookPlaying, action: onPlay)
                .accessibilityLabel("play \(book.title)")
                .padding(.trailing, KimaSpacing.lg)
        }
    }

    private var rowContent: some View {
        HStack(spacing: KimaSpacing.md) {
            // Sequence slot — waveform when this book is actively playing, adaptive-accent
            // number when loaded-but-paused, muted number otherwise. Same idiom as TrackRow's
            // leading slot elsewhere in the app.
            Group {
                if isThisBookPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .medium))
                } else {
                    Text("\(sequenceNumber)")
                        .font(KimaType.body.monospacedDigit())
                }
            }
            .foregroundStyle(isThisBookLoaded ? env.accent.color : KimaColor.textMuted)
            .frame(width: 24, alignment: .center)

            // Cover-forward thumbnail — larger than a plain list icon so the series reads as
            // a shelf of books, not a bare table (brief: "cover-forward").
            CoverArtImage(coverId: book.coverUrl, size: 112, cornerRadius: KimaRadius.image, placeholderSymbol: "book")
                .frame(width: 56, height: 56)
                .kimaShapeShadow(cornerRadius: KimaRadius.image, opacity: 0.4, radius: 6, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                        .strokeBorder(KimaColor.hairline, lineWidth: 1)
                )

            // Title + narrator/author
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(book.title.lowercased())
                    .font(KimaType.captionStrong)
                    .foregroundStyle(isThisBookLoaded ? env.accent.color : KimaColor.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                let byline = book.narrator ?? book.author
                Text(byline.lowercased())
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: KimaSpacing.sm)

            // Progress + Duration (right-aligned)
            VStack(alignment: .trailing, spacing: KimaSpacing.xs) {
                if let label = progressLabel {
                    Text(label)
                        .font(KimaType.meta.monospacedDigit())
                        .foregroundStyle(progressColor)
                }
                Text(book.duration.lengthLabel)
                    .font(KimaType.caption.monospacedDigit())
                    .foregroundStyle(KimaColor.textMuted)
            }
        }
        .padding(.leading, KimaSpacing.lg)
        .padding(.trailing, KimaSpacing.md)
        .padding(.vertical, KimaSpacing.md)
        .contentShape(Rectangle())
    }
}
