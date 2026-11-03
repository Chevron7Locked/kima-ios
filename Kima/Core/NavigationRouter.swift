import Foundation

/// The compact-width tabs in tab-bar order. The raw value is what `-kima-tab` takes.
enum AppTab: Int, Hashable {
    case home, library, audiobooks, podcasts, more
}

/// Cross-tab navigation coordinator for notification deep-links. Held on AppEnvironment,
/// so any view can request navigation via `env.router`. Kept deliberately small: the only
/// deep-link targets today are playlist/album/artist (all LibraryRoute, Library tab) —
/// matching the web NotificationsTab getLink contract.
@MainActor
@Observable
final class NavigationRouter {
    /// Bound to AppShellView's TabView selection.
    var selectedTab: AppTab = .home
    /// One-shot "open the stats page" request (whats-new gate go-to-target →
    /// More tab, at the false-starts section).
    /// The More tab consumes it by presenting stats and clearing the flag.
    var statsRequest = false
    /// The hour-drill cell the stats clock asked to open. AppShellView presents it, not StatsView: a `.sheet`
    /// presented from inside a tab's NavigationStack publishes no accessibility elements, so the sheet and the
    /// page behind it vanish from the accessibility tree. Cleared when the sheet dismisses.
    var hourDrill: HourDrill?
    /// Requests the app-root vibe map. AppShellView presents it, not MoreView: a `.fullScreenCover` presented
    /// from inside a tab's NavigationStack publishes no accessibility elements, so VoiceOver gets nothing from
    /// the map. Same presentation-host defect as the hour drill sheet and the audit confirm.
    var showVibeMap = false
    /// Requests the quick issue-report sheet (More tab's "report a problem"). AppShellView presents it, for the
    /// same reason as the vibe map.
    var showIssueReporter = false
    /// A pending false-starts audit confirmation, presented by AppShellView
    /// (see StatsConfirm — dialogs from inside a tab publish no AX elements).
    var statsConfirm: StatsConfirm?
    /// Companion to statsRequest for the #false-starts anchor (whats-new gate
    /// only — a bare deep link opens stats at the top, web parity).
    var statsScrollToAudit = false

    /// A Library route awaiting consumption by LibraryView. Set by `open`, cleared by LibraryView
    /// once appended to its NavigationStack. (Per-tab typed paths can't share one route type, so
    /// we publish the tab-appropriate route and let that tab consume it.)
    var pendingLibraryRoute: LibraryRoute?

    /// Pushed-screen count per tab. Each tab root publishes its NavigationStack
    /// depth here (see `View.publishesNavDepth`). The floating activity bell is a ROOT-level
    /// affordance: it shows only when the active tab is at its root, so it never covers a pushed
    /// detail screen's native trailing toolbar (e.g. the album/artist edit button).
    var navDepthByTab: [AppTab: Int] = [:]

    /// True when the currently-selected tab is at its NavigationStack root (nothing pushed).
    var activeTabAtRoot: Bool { (navDepthByTab[selectedTab] ?? 0) == 0 }

    /// Resolve a notification to a deep-link and navigate. First-match priority mirrors the web
    /// NotificationsTab getLink logic: playlist > album > artist; no podcastId/audiobookId targets.
    func open(_ notification: KimaNotification) {
        guard let meta = notification.metadata else { return }
        let route: LibraryRoute?
        if let id = meta.playlistId      { route = .playlistDetail(id: id) }
        else if let id = meta.albumId    { route = .album(id: id) }
        else if let id = meta.artistId   { route = .artist(id: id) }
        else                             { route = nil }
        guard let route else { return }
        selectedTab = .library          // hosts album/artist/playlist
        pendingLibraryRoute = route
    }
}
