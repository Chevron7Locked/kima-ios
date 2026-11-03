import Foundation
import SwiftUI

/// Swipe / minimize / dismiss state for the floating mini-player. Owned as `@State` in `AppShellView` and shared
/// with `MiniPlayerBar` and `MiniPlayerEdgeTab`. Track change resets minimized + dismissed; playback resuming
/// while dismissed restores the card. Minimize and dismiss are visual only; playback is never stopped.
@Observable
@MainActor
final class MiniPlayerSwipeState {

    /// The single spring that drives every minimize / restore transition. Using ONE shared
    /// spring (rather than an explicit withAnimation here plus an implicit .animation on the
    /// shell container) keeps the whole edge tab — frame, chevron, and cover art — bouncing as
    /// one rigid unit. A slightly under-damped spring gives the tab a lively settle on arrival.
    static let minimizeSpring: Animation = .spring(response: 0.34, dampingFraction: 0.66)

    // MARK: - Visible state

    /// Horizontal translation during an active drag. 0 at rest.
    /// The card's `.offset(x:)` and `opacity` are driven by this value directly.
    var dragOffset: CGFloat = 0

    /// Card is minimized to the right-edge tab. Playback is unaffected.
    private(set) var isMinimized: Bool = false

    /// Card is fully dismissed (left-swipe + paused). Playback is unaffected.
    /// Resets automatically on track change or resume.
    private(set) var isDismissed: Bool = false

    // MARK: - Internal bookkeeping

    /// Last known track id — used to detect identity changes.
    private var lastTrackId: String?

    /// Guards against firing the threshold haptic more than once per drag.
    private var hapticFiredThisDrag: Bool = false

    // MARK: - Drag handling

    /// Update the drag offset in real-time. Capped to ±150pt.
    /// Call from `DragGesture.onChanged`.
    func onDragChanged(width: CGFloat) {
        dragOffset = max(-150, min(150, width))

        // Haptic once when crossing the ±80pt commit threshold (improvement over web).
        if !hapticFiredThisDrag, abs(dragOffset) >= 80 {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            hapticFiredThisDrag = true
        } else if abs(dragOffset) < 80 {
            hapticFiredThisDrag = false
        }
    }

    /// Commit the swipe on finger-up (call from `DragGesture.onEnded`); springs back below the threshold.
    /// `isPlaying` decides the left-swipe outcome; `onExpand` opens the full player.
    func onDragEnded(isPlaying: Bool, onExpand: () -> Void) {
        let committed = dragOffset
        hapticFiredThisDrag = false

        if committed > 80 {
            // Swipe right minimizes to the edge tab. The offset is not sprung back to 0: the bar holds its
            // rightward shift and fades while the edge tab slides in, one continuous motion; springing back would
            // tug the card against the swipe. restore()/sync() clear the held offset before the bar shows again.
            withAnimation(Self.minimizeSpring) {
                isMinimized = true
            }
        } else if committed < -80, isPlaying {
            // Swipe left + playing → expand full player. Recenter first.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragOffset = 0 }
            onExpand()
        } else if committed < -80 {
            // Swipe left + paused → dismiss. Recenter, then fade out.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragOffset = 0 }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isDismissed = true }
        } else {
            // Below threshold → spring back to rest, no state change.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragOffset = 0 }
        }
    }

    // MARK: - Reset

    /// Synchronize state with playback. Call on track-id change and on `isPlaying` change.
    ///
    /// Track change resets both flags; resume while dismissed restores.
    func sync(trackId: String?, isPlaying: Bool) {
        if let id = trackId, id != lastTrackId {
            // Track identity changed — reset both visual states.
            lastTrackId = id
            if isDismissed { isDismissed = false }
            if isMinimized {
                dragOffset = 0
                withAnimation(Self.minimizeSpring) { isMinimized = false }
            }
        } else if trackId != nil, isDismissed, isPlaying {
            // Resumed while dismissed → restore the card.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isDismissed = false
            }
        }
    }

    /// Bring the bar back on screen: a play request means the user wants to see and control
    /// what they just started, so both visual suppressions (minimized tab, swipe-dismissed) clear.
    func showBar() {
        dragOffset = 0
        if isMinimized { withAnimation(Self.minimizeSpring) { isMinimized = false } }
        if isDismissed { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isDismissed = false } }
    }

    /// Restore the card from the minimized edge-tab state. Called by `MiniPlayerEdgeTab`.
    func restore() {
        dragOffset = 0   // clear any held minimize offset so the restored bar sits centered
        withAnimation(Self.minimizeSpring) {
            isMinimized = false
        }
    }

    // MARK: - VoiceOver gesture equivalents (A-5)

    /// Minimize the card to the right-edge tab. VoiceOver equivalent of a right-swipe gesture.
    func minimize() {
        withAnimation(Self.minimizeSpring) {
            isMinimized = true
        }
    }

    /// Dismiss the card. VoiceOver equivalent of a left-swipe-while-paused gesture.
    func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isDismissed = true
        }
    }
}
