import SwiftUI
import UIKit

extension AppShellView {

    // MARK: - Floating mini-player overlay

    /// Gap from the bottom safe-area edge up to the tab bar's top (49pt if the read fails).
    var tabBarLift: CGFloat { tabBar.lift ?? MiniPlayerLayout.tabBarHeight }

    /// Positions the floating card (or minimized edge-tab) above the tab bar. A `VStack { Spacer; content }` in the
    /// root ZStack pushes it down without an opaque fill that would block TabView taps. Lift = measured tab bar top
    /// (`tabBarLift`) plus the gap; hidden while the keyboard is up. iPhone only.
    @ViewBuilder
    var miniPlayerOverlay: some View {
        // `isActive` (not `currentTrack != nil`) so podcasts + audiobooks — long-form playback that
        // has no `currentTrack` object — also get the persistent mini-player + a route to the full
        // player. Without this the bar never appeared for spoken audio (no way to pause/scrub).
        if (player.isActive || player.isPreparingPlayback), !swipeState.isDismissed {
            VStack(spacing: 0) {
                Spacer()
                if swipeState.isMinimized {
                    // Edge tab anchored to the trailing edge.
                    HStack {
                        Spacer()
                        MiniPlayerEdgeTab(swipeState: swipeState)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    // Floating card. iOS 18 .sidebarAdaptable shows a TOP tab bar on iPad, so a full-width bar looks
                    // stretched: cap and center it on regular width (the VStack also keeps it over the content
                    // area if the sidebar opens). iPhone (compact) stays full-width minus the horizontal inset.
                    MiniPlayerBar(swipeState: swipeState, onExpand: { showFullPlayer = true })
                        .onAppear { tabBar.refresh() }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                            if miniCardHeight != h { miniCardHeight = h }
                            tabBar.refresh()
                        }
                        .frame(maxWidth: hSizeClass == .regular ? 600 : .infinity)
                        .padding(.horizontal, MiniPlayerLayout.tabBarCapsuleInset)
                        // Insertion slides up from the bottom. Removal is opacity-only, not .move(.bottom): on
                        // minimize the bar fades out on the right (following the swipe, see dragOffset) as the edge
                        // tab slides in.
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            // Lift above the tab bar's measured top edge plus the gap. `.ignoresSafeArea(.keyboard)`
            // keeps this frame from shrinking under the keyboard (the card is also hidden then).
            .padding(.bottom, tabBarLift + MiniPlayerLayout.cardGap)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // No implicit .animation(value: isMinimized): every isMinimized change is already wrapped
            // in withAnimation(MiniPlayerSwipeState.minimizeSpring), and a second spring here made
            // the edge tab and its cover art move on different curves.
        }
    }

    // MARK: - Activity bell overlay

    /// Floating bell pinned top-trailing, respecting the safe area. On a plain-http connection a
    /// ConnectionSecurityBadge shows beside it: calm "Private network" for a LAN/Tailscale host, caution only for a
    /// genuinely public http host. Sits below toasts so it never occludes an error banner.
    var bellOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: KimaSpacing.sm) {
                Spacer()
                // Root-level only: hidden once a detail is pushed on the active tab so it never
                // covers a detail screen's own trailing controls.
                if env.router.activeTabAtRoot {
                    ActivityBell { showActivity = true }
                }
            }
            .padding(.trailing, KimaSpacing.lg - ActivityBell.touchInset)
            Spacer()
        }
        // Breathing room below the status bar / notch, measured to the disc rather than its wider touch area.
        .padding(.top, KimaSpacing.sm - ActivityBell.touchInset)
    }
}
