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
/// and clears it on sign-out so a new server gets a fresh one. Constructing it is inert (ticket 12): no
/// network activity, no global mutation — previews that build one stay offline. The signed-in session's
/// network lifecycle lives in `bootstrap`: RootView calls `bootstrap.start()` once the bag exists and
/// `bootstrap.stop()` on `.unauthenticated` BEFORE setting it to nil, so every loop stops on the main
/// actor first (see SSEManager.swift for why deinit can't do it).
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

    /// The session's network lifecycle: one `start()` opens the event stream, the warm-ticket
    /// keeper, sync polling, cover-art auth wiring, and the rotation observer; one `stop()` ends
    /// them in their safe order. Constructing this bag starts nothing (ticket 12).
    let bootstrap: SessionBootstrap

    /// `sessions` is the factory seam (ticket 08): every client and stream this bag builds rides
    /// it, so a unit test can stand a whole session on stub transports; previews build one and
    /// never start it, which is why they stay offline.
    init(server: KimaServer, sessions: any SessionFactory = .production) {
        self.server = server
        let apiClient = KimaAPIClient(server: server, credential: KimaCredential.fromKeychain(for: server),
                                      sessions: sessions)
        let playbackController = PlaybackController(server: server)
        let coordinator = PlaybackSyncCoordinator(controller: playbackController, client: apiClient)
        let sseManager = SSEManager(sessions: sessions)
        self.client = apiClient
        self.player = playbackController
        self.sync = coordinator
        self.events = sseManager
        self.router = NavigationRouter()
        self.whatsNew = WhatsNewGateModel(client: apiClient)
        self.issueReports = IssueReportStore()
        // Wire syncHook before any start() so no mutation events are missed.
        // Weak capture of coordinator breaks the potential AppEnvironment → player →
        // syncHook closure → coordinator retain cycle.
        playbackController.syncHook = { [weak coordinator] in coordinator?.scheduleStateSave() }
        // Wire the API client so music-track loaders can fetch a stream ticket.
        playbackController.apiClient = apiClient
        // Play reporting: the listen meter POSTs /plays fire-and-forget (web parity).
        playbackController.attachPlayReporting(client: apiClient)
        self.bootstrap = SessionBootstrap(server: server, client: apiClient, player: playbackController,
                                          sync: coordinator, events: sseManager)
    }
}
