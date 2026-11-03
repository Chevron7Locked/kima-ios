import SwiftUI
import OSLog

/// Route-delivery breadcrumbs (category `route`) — read with
/// `xcrun simctl spawn booted log show --info --predicate 'category == "route"'`.
private let routeLog = Logger(subsystem: "com.chevron7locked.kima", category: "route")

extension AppShellView {

    // MARK: - Player deep-link delivery (kima://queue · kima://sleep-timer)

    /// Consume a latched PlayerRoute and present the requested surface. The route stays pending while the full
    /// player is up (FullPlayerView consumes it there; its sheets would stack on or hide behind the cover) and for
    /// a queue route on an idle player (server hydration can activate the player seconds after launch). The
    /// isActive edge below drops a stale queue route once a session starts.
    func deliverPlayerRoute() {
        routeLog.notice("deliver pending=\(String(describing: env.playerRoute.pending), privacy: .public) full=\(self.showFullPlayer) active=\(self.env.player.isActive)")
        guard let route = env.playerRoute.pending else { return }
        guard !showFullPlayer else { return }
        switch route {
        case .queue:
            // Long-form sessions have an EMPTY track queue but a live mini-player —
            // the right test is player activity, not queue emptiness.
            guard env.player.isActive else { return }
            _ = env.playerRoute.take()
            showQueueRouteSheet = true
        case .sleepTimer:
            _ = env.playerRoute.take()
            showSleepRouteSheet = true
        }
    }
}
