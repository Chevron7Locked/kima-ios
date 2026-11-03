import Foundation

// MARK: - Player deep-link routes (kima://queue · kima://sleep-timer)
// Two exact hosts beside the share link; KimaApp.onOpenURL's `kima://share/<token>` validator stays the gate.
// Delivery: KimaApp / debug arg -> router.request(_:) -> AppShellView consumes on change and once on appear
// (so a pre-auth route survives). Consuming clears the route.

enum PlayerRoute: Equatable, Sendable {
    case queue
    case sleepTimer
}

/// Exact-host parser shared by the URL handler and the debug arg. Returns nil for
/// anything it does not own (share links keep flowing to validateShareDeepLink
/// untouched; unknown hosts are dropped exactly as before).
func parsePlayerRoute(from url: URL) -> PlayerRoute? {
    guard url.scheme == "kima" else { return nil }
    // kima://queue and kima://sleep-timer both arrive as host (or path for the
    // trailing-slash variants a user might paste).
    let key = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
    switch key {
    case "queue":       return .queue
    case "sleep-timer": return .sleepTimer
    default:            return nil
    }
}

@MainActor
@Observable
final class PlayerRouteRouter {
    /// Process-wide router. AppEnvironment exposes this same instance as
    /// `env.playerRoute` for views; KimaApp's onOpenURL uses the static directly
    /// because URL delivery can precede environment injection.
    static let shared = PlayerRouteRouter()

    private(set) var pending: PlayerRoute?

    func request(_ route: PlayerRoute) { pending = route }

    /// Read-and-clear accessor (single-consumer semantics — a route is delivered once).
    func take() -> PlayerRoute? {
        defer { pending = nil }
        return pending
    }
}
