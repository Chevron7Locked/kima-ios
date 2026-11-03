import Foundation
import Observation

// MARK: - Notification names

extension Notification.Name {
    /// Posted by `KimaAPIClient.refreshAccessToken()` after a successful token rotation so
    /// `AppEnvironment` can drop its cached stream ticket.
    static let kimaAccessTokenRotated = Notification.Name("kima.accessTokenRotated")

    /// Posted by `SSEManager` when a ticket mint or stream connection returns 401/403,
    /// indicating the session has expired and the shell should prompt for re-authentication.
    static let kimaSSEAuthFailed = Notification.Name("kima.sseAuthFailed")

    /// Posted by the podcast screen after an unsubscribe (object: the podcast id) so "my podcasts"
    /// drops the show without a refresh.
    static let kimaPodcastUnsubscribed = Notification.Name("kima.podcastUnsubscribed")
}

/// Authenticated-scope dependency container, one per user session. RootView creates it on `.authenticated`
/// and clears it on sign-out so a new server gets a fresh one.
/// RootView must call `events.teardown()` on `.unauthenticated` BEFORE setting it to nil, so the SSE stream and
/// observers stop on the main actor first (see SSEManager.swift for why deinit can't do it).
@MainActor
@Observable
final class AppEnvironment {
    /// Screen width in points, measured once at the shell root; every tab's scroll column reads it to pin content
    /// to the viewport (see kimaViewportWidth). It lives here, not in the SwiftUI environment, because TabView
    /// hosts each tab in its own UIKit hosting controller and custom environment values don't cross that bridge.
    var viewportWidth: CGFloat = 0

    let server: KimaServer
    let client: KimaAPIClient

    /// Audio playback controller. One instance per
    /// session; injected into the SwiftUI environment by RootView alongside this object
    /// so all tabs and detail views share the same player state.
    let player: PlaybackController

    /// Cross-device playback-state sync coordinator. Owns the 1-second debounced
    /// save and 30-second poll loops. Wired to `player.syncHook` so queue/index/shuffle
    /// mutations auto-schedule a server save without the player knowing about networking.
    let sync: PlaybackSyncCoordinator

    /// SSE real-time engine. Owns the persistent GET /api/events stream, dispatches
    /// notification and progress events, and exposes observable state + action methods
    /// so the Activity panel and download views stay live without polling.
    let events: SSEManager

    /// Cross-tab navigation coordinator for notification deep-links.
    /// Views reach this via `env.router.open(_:)` to push Library destinations
    /// from the Activity sheet without knowing about AppShellView's tab state.
    let router: NavigationRouter

    /// Player-surface deep-link routes (kima://queue · kima://sleep-timer). Latched here
    /// because URL delivery can arrive before AppShellView exists; the shell consumes it.
    /// Same instance as PlayerRouteRouter.shared (see KimaApp.onOpenURL).
    let playerRoute = PlayerRouteRouter.shared

    /// Shared Radio view model. Owned here (not in LibraryRadioSection or RadioView) so the
    /// genre+decade network calls happen once per session — fetched on the first appearance of
    /// either the Home section or the full Radio screen, whichever comes first.
    let radioViewModel = RadioViewModel()

    /// App-wide Add-to-Playlist presenter. Any surface (context menu, hero button, track row)
    /// calls `env.playlistPicker.present(_:)`; `AppShellView` hosts the sheet off its `source`.
    let playlistPicker = PlaylistPickerModel()
    /// The activity sheet's tab and loaded lists, kept between opens.
    let activity = ActivityStore()

    /// Vibe Map view-model. Owned here (not in VibeMapView) so state survives fullScreenCover
    /// dismiss/reopen. VibeMapView receives it as `@Bindable var vm`.
    let vibeMapViewModel = VibeMapViewModel()

    /// What's-new release-window gate. Owned here (not in AppShellView) so the pending
    /// queue is fetched ONCE per authenticated session and shared across
    /// remounts. AppEnvironment's lifetime is exactly one
    /// authed session (created in RootView, nilled on sign-out).
    let whatsNew: WhatsNewGateModel

    /// Device-level connectivity monitor. Exposed so shell overlays and feature views can
    /// react to offline/online transitions without each spinning up their own NWPathMonitor.
    let network = NetworkMonitor()

    /// Whether this listener may start downloads; download controls read it.
    let acquire = AcquirePermission()

    /// Shared on-device AI service (FoundationModels, iOS 26+). Cheap to construct: it only reads model
    /// availability and never downloads or starts a session. AI features go through `env.intelligence`, not
    /// FoundationModels directly.
    let intelligence = KimaIntelligence()

    /// On-phone issue-report log. Filed from the More tab's "report a problem" row, listed,
    /// exported and cleared from Settings.
    let issueReports: IssueReportStore

    /// Player accent: the playing track's map colour through the logo gradient, or brand amber
    /// when the track has no colour. Crossfaded on change via `withAnimation` at the call site.
    var accent: FilamentAccent = .brand

    /// True when `accent` came from a real map colour (drives the full player's top glow).
    var accentHasColour = false

    /// Cover-art palette driving the ambient field backdrop. Loaded on first appearance and
    /// on track change with a 0.6s crossfade (see AppShellView). Nil for long-form content.
    var ambientPalette: CoverArtPalette? = nil

    /// Recompute `accent` from the playing track's map colour.
    func refreshAccent(from track: Track?) {
        #if DEBUG
        // Screenshot hook: `-kima-colour <0…1>` forces the player colour to that gradient share.
        if let i = CommandLine.arguments.firstIndex(of: "-kima-colour"),
           i + 1 < CommandLine.arguments.count, let v = Double(CommandLine.arguments[i + 1]) {
            accent = FilamentAccent(colour: v)
            accentHasColour = true
            return
        }
        #endif
        let resolved = PlayerAccentResolver.resolve(trackId: track?.id) { [vibeMapViewModel] in
            vibeMapViewModel.colour(for: $0)
        }
        accent = resolved.accent
        accentHasColour = resolved.hasColour
        #if DEBUG
        if let id = track?.id {
            print("accent: \(id) colour -> \(resolved.hasColour ? "gradient" : "brand")")
        }
        #endif
    }

    @ObservationIgnored private var tokenObserver: NSObjectProtocol? = nil

    init(server: KimaServer) {
        self.server = server
        let apiClient = KimaAPIClient(server: server, credential: KimaCredential.fromKeychain(for: server))
        let playbackController = PlaybackController(server: server)
        let coordinator = PlaybackSyncCoordinator(controller: playbackController, client: apiClient)
        let sseManager = SSEManager()
        self.client = apiClient
        self.player = playbackController
        self.sync = coordinator
        self.events = sseManager
        self.router = NavigationRouter()
        self.whatsNew = WhatsNewGateModel(client: apiClient)
        self.issueReports = IssueReportStore()
        // Wire syncHook before calling start() so no mutation events are missed.
        // Weak capture of coordinator breaks the potential AppEnvironment → player →
        // syncHook closure → coordinator retain cycle.
        playbackController.syncHook = { [weak coordinator] in coordinator?.scheduleStateSave() }
        // Wire the API client so music-track loaders can fetch a stream ticket.
        playbackController.apiClient = apiClient
        // Mint the stream ticket ahead of the first tap: every play path mints one inline, so the
        // first play of a session would otherwise pay a round trip before the player gets a URL.
        // AppEnvironment is authenticated-scope (see the type doc), so this is a mint at sign-in.
        playbackController.startKeepingStreamTicketWarm()
        // Play reporting: the listen meter POSTs /plays fire-and-forget (web parity).
        playbackController.attachPlayReporting(client: apiClient)
        coordinator.start()
        // Start the SSE stream; the manager also fires an initial refreshNotifications() Task.
        sseManager.start(client: apiClient, server: server)
        // Configure ImageCache to send the auth header on cover-art requests to our server.
        // The closure captures `apiClient` (the actor), re-reading the credential on each miss
        // so token refreshes and login/logout are handled without re-configuring.
        Task { await ImageCache.shared.configure(serverHost: server.baseURL.host(percentEncoded: false)) { await apiClient.authHeader() } }
        // Observe token rotations so the cached stream ticket is dropped. Weak
        // capture prevents a retain cycle (block → self → tokenObserver → block). After
        // AppEnvironment deinits, the guard ensures the block is a no-op until the next
        // NotificationCenter GC removes it.
        tokenObserver = NotificationCenter.default.addObserver(
            forName: .kimaAccessTokenRotated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue: .main delivers on the main queue, but the block is a
            // nonisolated context — hop so the mutation of the @MainActor
            // property is isolation-checked (compiler warning otherwise).
            Task { @MainActor [weak self] in
                // Also drop the cached stream ticket so the next play request fetches a fresh one.
                await self?.client.invalidateStreamTicket()
                // And re-mint now: the warm ticket has to follow the new token, and the keeper's
                // own sleep runs to half the ticket's lifetime — hours, for a 4-hour ticket.
                self?.player.stopKeepingStreamTicketWarm()
                self?.player.startKeepingStreamTicketWarm()
            }
        }
    }

    deinit {
        if let obs = tokenObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}
