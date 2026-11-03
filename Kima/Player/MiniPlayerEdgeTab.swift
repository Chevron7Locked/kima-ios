import SwiftUI

/// Minimized tab on the trailing edge, shown after the mini-player card is swiped right. Rounds only the left
/// corners and matches the card's skin (raised surface, hairline stroke, amber progress strip).
/// Tapping it calls `swipeState.restore()` to bring the card back.
struct MiniPlayerEdgeTab: View {

    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env

    /// Shared swipe state — `restore()` is called on tap.
    var swipeState: MiniPlayerSwipeState

    // MARK: - Layout

    private let leadingRadius: CGFloat = KimaRadius.card
    private let coverSize:     CGFloat = 48

    // MARK: - Body

    var body: some View {
        Button(action: swipeState.restore) {
            // Content-sized tab: tabContent drives the size; hairline stroke on top.
            tabContent
                .clipShape(leftRoundedShape(radius: leadingRadius))
                .overlay(
                    leftRoundedShape(radius: leadingRadius)
                        .strokeBorder(KimaColor.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("restore player")
        .shadow(color: .black.opacity(0.40), radius: 16, x: -4, y: 4)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: - Tab content

    // The progress strip is a top overlay, not a VStack row: PlayerProgressStrip is width-greedy, and as a
    // VStack member it stretched the tab to full width, defeating the trailing-edge anchor. As an overlay it
    // takes the content width. (In MiniPlayerBar the greediness is right: the bar is full-width.)
    @ViewBuilder
    private var tabContent: some View {
        contentRow
            .background(innerBackground)
            .overlay(alignment: .top) {
                PlayerProgressStrip()
            }
    }

    /// Raised surface matching the mini-player card.
    private var innerBackground: some View {
        ZStack {
            KimaColor.surfaceRaised              // #140B18
            env.accent.color.opacity(0.05)       // very faint adaptive warmth
        }
    }

    // MARK: - Content row

    /// Chevron-left + cover art.
    private var contentRow: some View {
        HStack(spacing: KimaSpacing.sm) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(KimaColor.textPrimary)

            if let track = player.currentTrack {
                AlbumSleeveThumbnail(
                    coverId: track.album?.coverArt,
                    size: coverSize,
                    cornerRadius: KimaRadius.image,
                    shadowRadius: 5,
                    shadowOpacity: 0.40,
                    shadowY: 2,
                    animationId: AnyHashable(track.id)
                )
            }
        }
        .padding(.leading, KimaSpacing.md)
        .padding(.trailing, KimaSpacing.sm)
        .padding(.vertical, KimaSpacing.md)
    }

    // MARK: - Helpers

    /// A shape rounded only on the leading (left) side — right corners are square.
    private func leftRoundedShape(radius: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius:     radius,
            bottomLeadingRadius:  radius,
            bottomTrailingRadius: 0,
            topTrailingRadius:    0
        )
    }
}
