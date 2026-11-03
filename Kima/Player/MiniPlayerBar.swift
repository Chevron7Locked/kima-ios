import SwiftUI
import UIKit

// MARK: - Layout constants

/// Named constants for the floating mini-player card placement. `tabBarHeight` is the lift used until the live
/// tab bar reports its frame. `tabBarCapsuleInset` is how far the floating bar's capsule sits in from each screen
/// edge (measured 20.7 pt on iPhone 16e and 18 Pro Max); the public tab bar frame exposes no capsule edges.
enum MiniPlayerLayout {
    static let tabBarHeight:       CGFloat = 49
    static let tabBarCapsuleInset: CGFloat = 21
    static let cardGap:            CGFloat = 8
    static let horizontalInset:    CGFloat = 8
    /// Height of the card: the 44pt cover plus 8pt padding above and below.
    static let cardHeight:         CGFloat = 60
    /// The fade above the solid bottom ground, where content dissolves before it reaches the card.
    static let groundFade:         CGFloat = 32
    /// The shorter fade when only the tab bar shows, so pages reserve less room with nothing playing.
    static let groundFadeBare:     CGFloat = 20
}

// MARK: - MiniPlayerBar

/// Floating mini-player card above the tab bar. Drag right past 80 pt minimizes to the edge tab; drag left past
/// 80 pt opens the full player when playing and dismisses the card when paused. Drag is capped at 150 pt,
/// opacity fades, below the threshold it springs back, and a haptic fires once at the threshold.
struct MiniPlayerBar: View {

    @Environment(PlaybackController.self) var player
    @Environment(AppEnvironment.self) var env
    @Environment(ToastCenter.self) var toast

    /// True while a `TrackTransferable` drag hovers over the bar — drives the drop-zone lift.
    @State private var dropTargeted = false

    /// Shared swipe / minimize / dismiss state — owned by `AppShellView`.
    var swipeState: MiniPlayerSwipeState
    /// Called when the user expands to the full player.
    var onExpand: () -> Void

    private let cardRadius:  CGFloat = 14
    private let coverSize:   CGFloat = 44

    // MARK: - Body

    var body: some View {
        Group {
            if let display {
                cardShell(display: display)
                    .kimaShapeShadow(cornerRadius: cardRadius, opacity: 0.50, radius: 14, y: 5)
                    .offset(x: swipeState.dragOffset)
                    .opacity(dragOpacity)
                    // Play Next via drag: a track row dragged from a list and dropped onto the
                    // Now Playing bar lands immediately after the current track. The payload is
                    // the shared `TrackTransferable` (playlist rows + future draggable surfaces).
                    // `isTargeted` drives a lift highlight so the drop zone reads while dragging.
                    .dropDestination(for: TrackTransferable.self) { payload, _ in
                        guard let transfer = payload.first else { return false }
                        announcePlayNext(player.playNext(transfer.track), in: toast)
                        return true
                    } isTargeted: { targeted in
                        dropTargeted = targeted
                    }
                    // simultaneousGesture (not .gesture): child tap/button gestures beat a parent
                    // .gesture(), so the swipe-to-minimize would never fire over the play/next/expand
                    // controls. Recognizing simultaneously lets taps hit the buttons while a real
                    // horizontal drag (>10pt) still drives minimize/dismiss.
                    .simultaneousGesture(dragGesture)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: display?.id)
    }

    // MARK: - Now-playing display (unifies music + long-form)

    /// A tiny presentation struct so the bar renders identically for a music `Track` and for
    /// long-form (podcast / audiobook) content, which has no `currentTrack` object. Nil when nothing is loaded.
    private struct NowPlayingDisplay: Equatable {
        let id: AnyHashable
        let title: String
        let artist: String
        let coverId: String?
        let directURL: URL?
        let isLongForm: Bool
    }

    private var display: NowPlayingDisplay? {
        if let track = player.currentTrack {
            return NowPlayingDisplay(
                id: AnyHashable(track.id),
                title: track.effectiveTitle,
                artist: track.artist?.name ?? "unknown artist",
                coverId: track.album?.coverArt,
                directURL: nil,
                isLongForm: false
            )
        }
        if player.isPreparingPlayback, let pending = player.upcomingTrack {
            // The tap's feedback: the bar appears with the track it is going to play, before the
            // stream resolves. Cover art arrives with the same fetch, so it stays a placeholder.
            return NowPlayingDisplay(
                id: AnyHashable(pending.id),
                title: pending.effectiveTitle,
                artist: pending.artist?.name ?? "unknown artist",
                coverId: pending.album?.coverArt,
                directURL: nil,
                isLongForm: false
            )
        }
        if player.playbackType.isLongForm, let meta = player.longFormNowPlayingMeta {
            let stableId: String
            if case .podcastEpisode(_, let ep, _) = player.playbackType { stableId = ep.id }
            else { stableId = meta.title }
            return NowPlayingDisplay(
                id: AnyHashable(stableId),
                title: meta.title,
                artist: meta.artist,
                coverId: nil,
                directURL: meta.coverURL,
                isLongForm: true
            )
        }
        return nil
    }

    // MARK: - Card shell

    @ViewBuilder
    private func cardShell(display: NowPlayingDisplay) -> some View {
        innerContent(display: display)
            .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .strokeBorder(KimaColor.hairline, lineWidth: 1)
            )
            // Drop-zone affordance: a quiet accent wash + brighter border while a track
            // drag hovers over the bar (drop-target feedback; accent follows the vibe).
            .background(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(env.accent.color.opacity(dropTargeted ? 0.16 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .strokeBorder(
                        dropTargeted ? env.accent.color.opacity(0.85) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .animation(.easeOut(duration: 0.15), value: dropTargeted)
    }

    // MARK: - Inner content

    @ViewBuilder
    private func innerContent(display: NowPlayingDisplay) -> some View {
        VStack(spacing: 0) {
            PlayerProgressStrip(height: 2)
            contentRow(display: display)
        }
        .background(innerBackground)
    }

    // MARK: - Background

    /// A solid neutral fill with a faint now-playing accent wash from the leading edge.
    private var innerBackground: some View {
        ZStack {
            KimaColor.surfaceRaised
            LinearGradient(
                colors: [env.accent.color.opacity(0.10), .clear],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    // MARK: - Content row

    @ViewBuilder
    private func contentRow(display: NowPlayingDisplay) -> some View {
        HStack(spacing: KimaSpacing.md) {
            // Tap-to-expand is a tap GESTURE, not a Button: a Button captures the touch and
            // swallows the horizontal drag, so swipe-to-minimize never fired over the cover/title.
            // A TapGesture coexists with the card's DragGesture — tap expands, drag minimizes.
            HStack(spacing: KimaSpacing.md) {
                coverArt(display: display)
                trackInfo(display: display)
            }
            .contentShape(Rectangle())
            .onTapGesture { onExpand() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(display.title), \(display.artist)")
            .accessibilityIdentifier("expand-player")   // stable test hook (label is dynamic)
            .accessibilityHint("opens the full player")
            .accessibilityAction(named: "expand player") { onExpand() }
            .accessibilityAction(named: "minimize player") { swipeState.minimize() }
            .accessibilityAction(named: "dismiss player") { swipeState.dismiss() }

            Spacer(minLength: 0)
            if !display.isLongForm { NowPlayingVibeButton() }
            NowPlayingPlayButton().padding(.trailing, 2)  // optical nudge off the bar's edge
        }
        .modifier(MiniVibeRelay())
        .padding(.horizontal, KimaSpacing.md)
        .padding(.vertical, KimaSpacing.sm)
    }

    // MARK: - Cover art

    @ViewBuilder
    private func coverArt(display: NowPlayingDisplay) -> some View {
        AlbumSleeveThumbnail(
            coverId: display.coverId,
            // Long-form art is a resolved URL (episode/book cover), not a cover id.
            directURL: display.directURL,
            size: coverSize,
            cornerRadius: KimaRadius.card,
            shadowRadius: 6,
            shadowOpacity: 0.45,
            shadowY: 3,
            animationId: display.id
        )
    }

    // MARK: - Track info

    @ViewBuilder
    private func trackInfo(display: NowPlayingDisplay) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            if player.audioError != nil {
                HStack(spacing: KimaSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(KimaColor.danger.opacity(0.9))
                    Text("playback error")
                        .font(KimaType.bodyStrong)
                        .foregroundStyle(KimaColor.danger.opacity(0.9))
                        .lineLimit(1)
                }
                Text("tap retry to reconnect")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.danger.opacity(0.7))
                    .lineLimit(1)
            } else {
                Text(display.title.lowercased())
                    .font(KimaType.bodyStrong)
                    .tracking(0)
                    .foregroundStyle(KimaColor.textPrimary)
                    .lineLimit(1)
                Text(display.artist.lowercased())
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#Preview {
    let env = AppEnvironment(server: KimaServer(baseURL: URL(string: "http://preview.local")!))
    let toast = ToastCenter()
    ZStack {
        KimaColor.base.ignoresSafeArea()
        MiniPlayerBar(swipeState: MiniPlayerSwipeState(), onExpand: {})
            .padding(.horizontal, MiniPlayerLayout.horizontalInset)
    }
    .environment(env)
    .environment(env.player)
    .environment(toast)
}
