import SwiftUI

// MARK: - PlayerArtworkView

/// Hero artwork area of the full player: the cover with glow halo, horizontal swipe to skip (rubber-band 0.5,
/// skip-hint chevrons past 20 pt), and a scale that eases back while paused. Swaps to `LyricsPanel` in the same
/// slot when `showLyrics` is true. All swipe state lives here so FullPlayerView stays thin.
struct PlayerArtworkView: View {

    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    @Binding var showLyrics: Bool
    /// Largest side of the cover and the lyrics panel: 340 on iPhone, bigger on iPad (`FullPlayerLayout`).
    var maxSide: CGFloat = FullPlayerLayout.phoneArtworkSide

    // MARK: - Swipe state (internal)

    @State private var coverOffset: CGFloat = 0
    @State private var coverDragActive: Bool = false
    @State private var showCoverViewer = false

    private let swipeThreshold: CGFloat = 60

    // MARK: - Body

    var body: some View {
        if showLyrics {
            LyricsPanel()
                .frame(maxWidth: maxSide)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
        } else {
            artworkStack
                .frame(maxWidth: .infinity)
                // Tap the hero cover → open it full-screen. Owned bool; presenter dismisses via
                // onClose (an @Environment(\.dismiss) inside would not reset this binding here).
                .fullScreenCover(isPresented: $showCoverViewer) {
                    let isLong = player.playbackType.isLongForm
                    let meta = player.longFormNowPlayingMeta
                    CoverImageViewer(
                        coverId: player.currentTrack?.album?.coverArt,
                        directURL: isLong ? meta?.coverURL : nil,
                        size: 1024,
                        title: isLong ? meta?.title : player.currentTrack?.effectiveTitle,
                        subtitle: isLong ? meta?.artist : player.currentTrack?.artist?.name,
                        onClose: { showCoverViewer = false }
                    )
                    .appEnvironment(env, toast)
                }
        }
    }

    // MARK: - Artwork

    private var artworkStack: some View {
        ZStack {
            // Glow halo: blurred now-playing accent gradient
            RoundedRectangle(cornerRadius: KimaRadius.hero, style: .continuous)
                .fill(glowGradient)
                .blur(radius: 28)
                .scaleEffect(1.14)     // halo bleeds a little past the cover boundary
                .opacity(0.55)
                // Decoration only: the scaled halo reaches past the cover and must not take taps meant for
                // the controls around it (the queue button above it on iPad).
                .allowsHitTesting(false)

            // Album art — square, capped at maxSide
            CoverArtImage(
                coverId: player.currentTrack?.album?.coverArt,
                // Long-form (audiobook/podcast) art is a resolved URL, not a library cover id.
                directURL: player.playbackType.isLongForm
                    ? player.longFormNowPlayingMeta?.coverURL : nil,
                size: maxSide > FullPlayerLayout.phoneArtworkSide ? 1024 : 512,
                cornerRadius: KimaRadius.hero,
                heroPlaceholder: true
            )
            .shadow(color: .black.opacity(0.60), radius: 24, x: 0, y: 12)
            .overlay(
                RoundedRectangle(cornerRadius: KimaRadius.hero, style: .continuous)
                    .strokeBorder(KimaColor.hairline, lineWidth: 1)
            )
            .overlay(skipHintChevrons)
            .gesture(coverSwipeGesture)
            // Tap opens the full-screen lightbox. A TapGesture needs zero movement and the swipe DragGesture needs
            // 10 pt or more, so a still tap opens the viewer and a horizontal drag skips. It is simultaneous (not
            // `.gesture`, which would compete for the same recognizer slot) so both live on one cover.
            .simultaneousGesture(TapGesture().onEnded { showCoverViewer = true })
            // Scale breathe: playing → full size, paused → slightly pulled back
            .scaleEffect(player.isPlaying ? 1.0 : 0.925)
            .animation(.spring(duration: 0.65, bounce: 0.28), value: player.isPlaying)
        }
        // Square, so the halo matches the cover instead of stretching into the height left over.
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: maxSide)
        // Rubber-band translate + opacity while swiping
        .offset(x: coverOffset)
        .opacity(1.0 - Double(abs(coverOffset)) / 200.0)
        .animation(coverDragActive ? nil : .spring(duration: 0.38, bounce: 0.22),
                   value: coverOffset)
        // A-2/A-3: VoiceOver label + swipe-gesture alternatives for non-sighted users.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("album art: \(player.currentTrack?.effectiveTitle ?? "unknown")")
        .accessibilityAddTraits(.isImage)
        .accessibilityAction(named: "skip to next") { player.next() }
        .accessibilityAction(named: "skip to previous") { player.previous() }
    }

    // MARK: - Glow gradient

    private var glowGradient: LinearGradient {
        LinearGradient(
            colors: [
                env.accent.color.opacity(0.22),
                Color.clear,
                env.accent.deep.opacity(0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Skip-hint chevrons

    /// Directional chevrons that fade in as the swipe offset crosses ±20 pt.
    private var skipHintChevrons: some View {
        ZStack {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(KimaColor.textSecondary)
                .padding(.leading, KimaSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(coverOffset > 20
                    ? Double(min(1.0, (coverOffset - 20) / 60.0)) : 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(KimaColor.textSecondary)
                .padding(.trailing, KimaSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(coverOffset < -20
                    ? Double(min(1.0, (-coverOffset - 20) / 60.0)) : 0)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Cover swipe gesture

    private var coverSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let tx = value.translation.width
                let ty = value.translation.height
                // Only activate for predominantly horizontal motion
                guard abs(tx) > abs(ty) * 0.75 else { return }
                coverDragActive = true
                coverOffset = tx * 0.5   // rubber-band: artwork follows at 0.5×
            }
            .onEnded { value in
                coverDragActive = false
                let tx = value.translation.width
                if      tx >  swipeThreshold { player.previous() }
                else if tx < -swipeThreshold { player.next() }
                withAnimation(.spring(duration: 0.38, bounce: 0.22)) {
                    coverOffset = 0
                }
            }
    }
}
