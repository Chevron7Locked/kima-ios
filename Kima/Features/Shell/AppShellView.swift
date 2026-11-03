import SwiftUI
import UIKit

/// Authenticated root shell. iPhone: five tabs (Home, Library, Audiobooks, Podcasts, More) with a floating
/// mini-player and a top-trailing bell. iPad: RegularShellView. More (MoreView) is the hub for everything else.
/// The mini-player is a custom overlay above the TabView (not tabViewBottomAccessory); the opaque
/// KimaColor.base behind the TabView prevents see-through.
struct AppShellView: View {
    let host: String
    let onSignOut: () -> Void
    /// Back to the address screen, keeping the stored credential (Settings "change server").
    let onChangeServer: () -> Void

    // Non-private so the extracted `baseTabView` (AppShellView+TabView.swift) can read it.
    @Environment(AppEnvironment.self) var env
    @Environment(PlaybackController.self) var player
    @Environment(\.horizontalSizeClass) var hSizeClass

    /// App-wide toast hub. Owned here (one instance per authenticated session) and
    /// injected via `.environment` so any descendant can post via `ToastCenter.show`.
    @State var toastCenter = ToastCenter()

    /// Controls FullPlayerView presentation. Set to true when the user taps the
    /// MiniPlayerBar expand zone (cover + title) or left-swipes while playing.
    @State var showFullPlayer = false

    /// Player deep-link sheet state (kima://queue · kima://sleep-timer while the full
    /// player is NOT up). When the full player IS up, the routes deliver inside it
    /// (FullPlayerView observes playerRoute.pending on appear — see deliverPlayerRoute).
    @State var showQueueRouteSheet = false
    @State var showSleepRouteSheet = false

    /// Controls ActivitySheet presentation. Toggled by ActivityBell tap.
    @State var showActivity = false

    /// True while the software keyboard is on-screen — set from the keyboard notifications (which
    /// fire exactly once per show/hide). The floating mini-player is hidden while it's true: a card
    /// can't be cleanly positioned around a keyboard mid-animation, and it sits behind the keyboard
    /// anyway. Hidden instantly (no animation) so there is no transaction that can flicker.
    @State var keyboardUp = false

    /// The shell's single full-screen cover (full player / vibe map), mirrored from
    /// `showFullPlayer || env.router.showVibeMap`. SwiftUI's presentation machinery fires reliably on
    /// a @State-driven isPresented; a computed binding over the router was observed changing (re-render,
    /// onChange fired) yet never created the cover window.
    @State var shellCoverPresented = false

    /// Swipe / minimize / dismiss state for the floating mini-player.
    @State var swipeState = MiniPlayerSwipeState()

    /// Tab bar position, read when the mini-player card appears; the card is placed from it.
    @State var tabBar = TabBarMetrics()

    /// Laid-out height of the floating card (0 until measured), for the clearance screens reserve.
    @State var miniCardHeight: CGFloat = 0

    /// True while the full mini player card shows above the tab bar (iPhone).
    var miniCardShowing: Bool {
        hSizeClass != .regular && player.isActive && !swipeState.isDismissed && !swipeState.isMinimized
            && miniCardHeight > 0
    }

    /// The bottom ground's fade: longer while the card shows, so content is gone before it reaches the card.
    var bottomFade: CGFloat {
        guard hSizeClass != .regular else { return 0 }
        return miniCardShowing ? MiniPlayerLayout.groundFade : MiniPlayerLayout.groundFadeBare
    }

    /// Room the bottom unit takes above the tab bar: the card and its gap while the card shows, plus the ground's
    /// fade, so the last row of a page stops where the fade starts.
    var miniPlayerFootprint: CGFloat {
        guard hSizeClass != .regular else { return 0 }
        return (miniCardShowing ? miniCardHeight + MiniPlayerLayout.cardGap : 0) + bottomFade
    }


    // MARK: - Body
    // Tab selection lives on env.router.selectedTab (NavigationRouter) so deep-links
    // from the Activity sheet can switch tabs programmatically. HomeView and the TabView
    // both bind directly to that value via a @Bindable local — single source of truth.

    var body: some View {
        let root = ZStack {
            // Opaque warm canvas fills the entire window — no system UI bleed through the
            // floating tab-bar margins or the home-indicator strip.
            KimaColor.base.ignoresSafeArea()
            // Viewport-width measurement for the tab scroll columns (kimaViewportWidth). Compact only: on iPhone
            // window == content column. On regular width RegularShellView measures the column itself; a second
            // writer here would keep re-pinning feeds wider than the column.
            if hSizeClass != .regular {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()

                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
                        if env.viewportWidth != w { env.viewportWidth = w }
                    }
            }

            if hSizeClass == .regular {
                // iPad: the 2-column shell (sidebar · content, with a docked now-playing bar) replaces the tab bar, the floating
                // mini-player and the top bell — the sidebar carries the bell, the docked bar carries playback.
                RegularShellView(
                    host: host,
                    onSignOut: onSignOut,
                    onChangeServer: onChangeServer,
                    onShowActivity: { showActivity = true },
                    onExpandPlayer: { showFullPlayer = true },
                    keyboardUp: keyboardUp
                )
                // Presented here, as on iPhone, so player routes (kima://queue) open inside it while it is up.
                .fullScreenCover(isPresented: shellCoverBinding) { shellCoverContent }
            } else {
                // iPhone: tab bar + floating mini-player + top-trailing activity bell.
                baseTabView
                    .environment(\.miniPlayerFootprint, miniPlayerFootprint)
                    .environment(\.kimaChromeExtent, KimaChromeExtent(
                        top: tabBar.windowTop,
                        bottom: tabBar.windowBottom + tabBarLift + miniPlayerFootprint,
                        bottomFade: bottomFade))
                    // Re-read the bar whenever the tab area's frame changes: at launch the card
                    // can appear before the bar is laid out, and its first read would be stale.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { _ in
                        tabBar.refresh()
                    }
                    .fullScreenCover(isPresented: shellCoverBinding) { shellCoverContent }
                miniPlayerOverlay
                    .opacity(keyboardUp ? 0 : 1)      // instant hide while the keyboard is up
                    .allowsHitTesting(!keyboardUp)
                bellOverlay
            }

            // Offline banner — persistent pill when device has no network path. Sits above the
            // content but below toasts; never blocks taps. iPad shows it over the content column.
            if hSizeClass != .regular { OfflineBannerPill() }

            // Toast overlay — topmost layer; transparent to taps.
            KimaToastOverlay()
        }
        .environment(toastCenter)
        .onChange(of: hSizeClass) { _, _ in tabBar.refresh() }
        // Mirror the cover requests into the @State flag that drives the single fullScreenCover. This sits
        // on the root: @State writes from onChange on the outer chain never re-rendered. Writes wait for
        // the next runloop, because SwiftUI drops @State writes made mid-update.
        .onChange(of: env.router.showVibeMap) { _, v in
            Task { @MainActor in shellCoverPresented = showFullPlayer || v }
        }
        .onChange(of: showFullPlayer) { _, v in
            Task { @MainActor in shellCoverPresented = v || env.router.showVibeMap }
        }
        return withObservers(withSheets(root))
            // Asks "replace song path?" for the mini player's vibe button; a cover over the shell asks instead.
            .vibeReplaceDialog(player: player, suppressed: showFullPlayer || env.router.showVibeMap)
            #if DEBUG
            .debugVibeReplaceMarker(player: player, id: "vibe-fake-replace-origin-shell")
            .modifier(DebugServerStateRunner(client: env.client))
            .task { await debugLaunchHooks() }
            #endif
    }

    /// The shell's ONE full player / vibe-map cover for iPad and iPhone: SwiftUI honors one
    /// presentation modifier per view, and it fires reliably only on the @State mirror (a computed
    /// binding over the router never fired). Vibe wins when both are requested; the mini player
    /// cannot be expanded under the cover.
    var shellCoverBinding: Binding<Bool> {
        Binding(
            get: { shellCoverPresented },
            set: { presented in
                shellCoverPresented = presented
                if !presented { showFullPlayer = false; env.router.showVibeMap = false }
            }
        )
    }

    @ViewBuilder var shellCoverContent: some View {
        if env.router.showVibeMap {
            VibeMapView(vm: env.vibeMapViewModel, onClose: { env.router.showVibeMap = false })
                .appEnvironment(env, toastCenter)
        } else {
            FullPlayerView()
                .appEnvironment(env, toastCenter)
        }
    }
}

// `.appEnvironment(env, toast)` — the shared presented-content env re-injection modifier —
// lives in DesignSystem/AppEnvironmentInjection.swift so every sheet/cover call site can use it.

// MARK: - Preview

#Preview {
    let env = AppEnvironment(server: KimaServer(baseURL: URL(string: "https://kima.example.com")!))
    AppShellView(host: "kima.example.com", onSignOut: {}, onChangeServer: {})
        .environment(env)
        .environment(env.player)
}
