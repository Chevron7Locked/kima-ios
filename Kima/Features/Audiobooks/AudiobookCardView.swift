import SwiftUI

// MARK: - AudiobookCardView

/// Audiobook card: the shared cover card with the title over the author, an amber progress bar along the cover's
/// foot while the book is part-read, a green check in the corner once finished, and a play badge when `onPlay` is
/// given. Fills the width it is offered (a grid column, or a caller's `.frame(width:)` in a rail).
struct AudiobookCardView: View {
    let bookId: String
    let coverId: String?
    let title: String
    let author: String
    /// Progress 0–100. Nil = never started (no bar shown).
    let progressPct: Double?
    var isFinished: Bool = false
    /// Optional play action. Nil (default) hides the play badge entirely — used by cards that
    /// have no single obvious book to start (e.g. a series card with no books yet).
    var onPlay: (() -> Void)? = nil
    let onTap: () -> Void

    @Environment(PlaybackController.self) private var player

    /// Whether this book is the one playing.
    private var isPlayingThis: Bool {
        player.isPlaying && player.isAudiobookLoaded(bookId)
    }

    var body: some View {
        KimaCoverCard(title: title, subtitle: author, titleLines: 2, isPlaying: isPlayingThis, onPlay: onPlay,
                      onTap: onTap) {
            CoverArtImage(coverId: coverId, size: 256, cornerRadius: 0, placeholderSymbol: "book")
                .overlay(alignment: .bottom) {
                    if !isFinished, let pct = progressPct, pct > 0 {
                        KimaProgressBar(fraction: pct / 100)
                            .padding(.horizontal, KimaSpacing.sm)
                            .padding(.bottom, KimaSpacing.sm)
                    }
                }
        } accessory: {
            if isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(KimaColor.positive)
                    .padding(KimaSpacing.sm)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
            }
        }
    }
}
