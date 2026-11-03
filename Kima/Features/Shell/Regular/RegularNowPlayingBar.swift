import SwiftUI

// MARK: - RegularNowPlayingBar

/// Docked playback bar for the iPad 2-column shell, pinned to the bottom of the content column only (the
/// sidebar stays clear). Cover and title/artist on the left (tap opens the full player), previous · play ·
/// next in the middle, then the seek line and the vibe button when the column is wide enough. Same look as the
/// iPhone mini player: solid raised surface, a whisper of the vibe from the leading edge, lowercase text.
struct RegularNowPlayingBar: View {
    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    /// Opens the full player.
    let onExpand: () -> Void

    @State private var width: CGFloat = 0

    /// Bar height (excluding the safe-area inset the parent adds below it). The shell reserves
    /// this much bottom space in the content column so the last row never hides under the bar.
    static let height: CGFloat = 64

    /// Narrower columns (Split View, the 11-inch portrait with the sidebar open) drop the seek line.
    private var showsScrubber: Bool { width >= 640 }

    var body: some View {
        HStack(spacing: KimaSpacing.lg) {
            expandZone
                .frame(maxWidth: showsScrubber ? 300 : .infinity, alignment: .leading)

            if showsScrubber { Spacer(minLength: 0) }

            transport

            if showsScrubber {
                Spacer(minLength: 0)
                DockedScrubber()
                    .frame(minWidth: 180, maxWidth: 360)
            }

            if !player.playbackType.isLongForm {
                NowPlayingVibeButton()
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .modifier(MiniVibeRelay())
        // Play Next via drag: same drop target as the iPhone mini-player — a track row
        // dragged from a list and released here lands right after the current track.
        .dropDestination(for: TrackTransferable.self) { payload, _ in
            guard let transfer = payload.first else { return false }
            announcePlayNext(player.playNext(transfer.track), in: toast)
            return true
        }
        // Solid surfaceRaised + a whisper of the vibe as a leading wash, same as the iPhone mini-player.
        // Opaque on purpose: a translucent bar lets feed content show through.
        .background {
            ZStack {
                KimaColor.surfaceRaised
                LinearGradient(
                    colors: [env.accent.color.opacity(0.10), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            // Bleed the solid surface into the bottom safe strip so it fully covers the
            // content scrolling under the bar.
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .top) {
            KimaHairline()
        }
    }

    // MARK: - Expand zone (cover + title/artist)

    private var expandZone: some View {
        Button(action: onExpand) {
            HStack(spacing: KimaSpacing.md) {
                AlbumSleeveThumbnail(
                    coverId: player.currentTrack?.album?.coverArt,
                    directURL: player.playbackType.isLongForm ? player.longFormNowPlayingMeta?.coverURL : nil,
                    size: 44,
                    cornerRadius: KimaRadius.card,
                    shadowRadius: 6,
                    shadowOpacity: 0.45,
                    shadowY: 3,
                    animationId: player.currentTrack?.id ?? player.longFormNowPlayingMeta?.title
                )

                VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                    // Long-form (audiobook/podcast) has no currentTrack — title/artist come from longFormNowPlayingMeta,
                    // as on the mini player. A missing artist hides the line.
                    Text(barTitle.lowercased())
                        .font(KimaType.bodyStrong)
                        .foregroundStyle(KimaColor.textPrimary)
                        .lineLimit(1)
                    if let artist = barArtist {
                        Text(artist.lowercased())
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("now playing: \(barTitle). open full player.")
    }

    private var barTitle: String {
        if let t = player.currentTrack { return t.effectiveTitle }
        return player.longFormNowPlayingMeta?.title ?? ""
    }

    private var barArtist: String? {
        if let a = player.currentTrack?.artist?.name { return a }
        return player.longFormNowPlayingMeta?.artist
    }

    // MARK: - Transport (previous · play/pause · next; ±30 s for long-form)

    private var transport: some View {
        HStack(spacing: KimaSpacing.xs) {
            if player.playbackType.isLongForm {
                transportButton("gobackward.30", label: "skip back 30 seconds") { player.skip(by: -30) }
                NowPlayingPlayButton()
                transportButton("goforward.30", label: "skip forward 30 seconds") { player.skip(by: 30) }
            } else {
                transportButton("backward.fill", label: "previous", enabled: player.canGoPrevious) { player.previous() }
                NowPlayingPlayButton()
                transportButton("forward.fill", label: "next", enabled: player.canGoNext) { player.next() }
            }
        }
    }

    /// Transport glyph, greyed and inert when `enabled` is false (the docked bar's
    /// next/previous use the player's `canGoNext`/`canGoPrevious` at the queue ends).
    private func transportButton(_ symbol: String, label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(KimaColor.textPrimary)
                .kimaDisabled()
                .frame(width: KimaLayout.minTouchTarget, height: KimaLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
