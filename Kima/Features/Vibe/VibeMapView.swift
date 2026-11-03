import SwiftUI

// MARK: - VibeMapView

/// Full-screen Vibe Map, presented as a `.fullScreenCover` from Home. Loads the projection through VibeMapViewModel
/// and hands the tracks to VibeMapField (Metal). States: loading, failed (retry), empty, loaded. Over the map: top
/// bar, mood legend, tool rail, the open panel or selected track's readout, mini-player. Long-press selects like a
/// tap; `vm.notice` shows as a toast. Overlay views are in VibeMapView+Overlay.swift.
struct VibeMapView: View {

    // Internal so the +Overlay extension can read these.
    @Bindable var vm: VibeMapViewModel  // owned by AppEnvironment; survives dismiss/reopen (#28)
    /// Close action supplied by the presenter, not `@Environment(\.dismiss)`: `dismiss()` fails to reset the
    /// `.fullScreenCover(isPresented:)` binding when presented from a NavigationStack nested in a `.sidebarAdaptable`
    /// TabView, so the map re-presented itself. The presenter sets its own state false (compact) or steers the
    /// sidebar (regular).
    let onClose: () -> Void
    @Environment(AppEnvironment.self) var env
    @Environment(PlaybackController.self) var player
    @Environment(ToastCenter.self) var toast

    // MARK: Shared mini-player state (mirrors AppShellView)

    @State var swipeState = MiniPlayerSwipeState()
    @State var showFullPlayer = false
    @State var safeAreaBottom: CGFloat = 34

    // MARK: Album navigation

    /// Album id for the album sheet; nil = sheet dismissed.
    @State var viewAlbumId: String? = nil

    /// Navigation path inside the album sheet.
    @State private var viewAlbumPath: [LibraryRoute] = []

    /// Artist id for the artist sheet; nil = sheet dismissed.
    @State var viewArtistId: String? = nil

    /// Navigation path inside the artist sheet.
    @State private var viewArtistPath: [LibraryRoute] = []

    /// The help list has been closed once (remembered, so it opens by itself on the first visit only).
    @AppStorage(VibeMapPrefs.helpSeenKey) var helpSeen = false

    /// The help list is open: on the first visit, or after the rail's help button.
    @State var helpOpen = !UserDefaults.standard.bool(forKey: VibeMapPrefs.helpSeenKey)

    /// The selected track's readout (global); the leader line from its star ends on its top edge.
    @State var readoutFrame: CGRect?

    /// The tool rail (global), which the leader line goes around.
    @State var railFrame: CGRect?

    /// Top of the bottom stack (panel or readout, then the mini player), bottom of the search list and
    /// bottom of the top bar with its mood chips (global); map labels keep out of all three.
    @State var bottomStackTop: CGFloat = .infinity
    @State var searchListBottom: CGFloat?
    @State var hudBottom: CGFloat?

    /// Height of the software keyboard over the screen; 0 when it is down.
    @State var keyboardHeight: CGFloat = 0

    /// Height of the screen the keyboard reported against, for the room left above it.
    @State var screenHeight: CGFloat = 0

    // MARK: Camera

    /// Incrementing trigger: each tap on the locate button flies the camera to the playing star.
    /// An int counter handles repeated presses cleanly.
    @State var locateTrigger = 0

    /// Incrementing trigger: flies the camera back to the whole-library view.
    @State var homeTrigger = 0

    /// Mood labels on the map (read by the overlay and the top-bar switch).
    @AppStorage(VibeMapPrefs.showLabelsKey) var showLabels = VibeMapPrefs.showLabelsDefault

    // MARK: - Body

    var body: some View {
        ZStack {
            // Warm near-black base — fills the entire screen including safe area.
            KimaColor.base.ignoresSafeArea()

            // Phase-driven content
            switch vm.phase {
            case .loading:
                loadingContent
            case .failed(let msg):
                failedContent(message: msg)
            case .loaded(let tracks):
                if tracks.isEmpty {
                    emptyContent
                } else {
                    mapField(tracks: tracks)
                }
            }
        }
        // The controls sit in overlays, so they can never size the screen: as ZStack children, a panel
        // taller than the space above the keyboard made the whole screen taller, and the cover moved
        // it up (top bar under the status bar). -kima-vibe-bare (DEBUG) hides them for screenshots.
        .overlay(alignment: .top) {
            if !VibeDebugFlags.bare { hud }
        }
        .overlay {
            // Bottom bar: mini-player (fullscreen offset — no tab bar), above the panels.
            if !VibeDebugFlags.bare { bottomOverlay }
        }
        // The keyboard covers the lower map instead of squeezing the panels (squeezed, the song path
        // list shrank to nothing).
        .ignoresSafeArea(.keyboard)
        .vibeReplaceDialog(player: player, suppressed: showFullPlayer)
        .onChange(of: vm.notice) { _, text in
            guard let text else { return }
            toast.show(text)
            vm.notice = nil
        }
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView()
                .appEnvironment(env, toast)
        }
        // Album detail sheet — presents AlbumDetailView in its own NavigationStack.
        .sheet(
            isPresented: Binding(
                get: { viewAlbumId != nil },
                set: { if !$0 { viewAlbumId = nil; viewAlbumPath = [] } }
            )
        ) {
            if let albumId = viewAlbumId {
                NavigationStack(path: $viewAlbumPath) {
                    AlbumDetailView(albumId: albumId, path: $viewAlbumPath)
                }
                .appEnvironment(env, toast)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { viewArtistId != nil },
                set: { if !$0 { viewArtistId = nil; viewArtistPath = [] } }
            )
        ) {
            if let artistId = viewArtistId {
                NavigationStack(path: $viewArtistPath) {
                    ArtistDetailView(artistId: artistId, path: $viewArtistPath)
                }
                .appEnvironment(env, toast)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        // The home-indicator inset only: with the keyboard up this inset grows to the keyboard's
        // height, which would float the bottom stack over it.
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: {
            if $0 < 100 { safeAreaBottom = $0 }
        }
        .onChange(of: player.currentTrack?.id) { _, id in
            swipeState.sync(trackId: id, isPlaying: player.isPlaying)
        }
        .onChange(of: player.isPlaying) { _, playing in
            swipeState.sync(trackId: player.currentTrack?.id, isPlaying: playing)
        }
        // Revalidate on every open without clearing the loaded state.
        .task {
            #if DEBUG
            if let map = VibeDebugSyntheticMap.responseIfRequested() ?? VibeDebugMapFile.responseIfRequested() {
                vm.apply(map)
                vm.applyDebugLaunchState()
                // Screenshot hook: opens the help list over whatever the launch state showed.
                if UserDefaults.standard.bool(forKey: "kima-vibe-help-open") { helpOpen = true }
                return
            }
            #endif
            await vm.backgroundRevalidate(client: env.client)
        }
        // The text search runs over the loaded map on every keystroke, like the web.
        .onChange(of: vm.searchQuery) { _, _ in vm.updateSearch() }
        .task(id: vm.searchMatches.top.map(\.id)) { await vm.nameSharedTitleAlbums(client: env.client) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screen = (note.object as? UIScreen)?.bounds.height ?? end.maxY
            keyboardHeight = max(0, screen - end.minY)
            screenHeight = screen
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onDisappear {
            // The map is session-scoped; nothing it started may outlive the screen or leave a prompt open.
            vm.stopPolling()
            vm.cancelOperations()
            player.resolveVibeReplace(false)
        }
    }

    // MARK: - HUD

    /// Top bar and mood chips, top-aligned. NOT ignoresSafeArea — clears the status bar.
    private var hud: some View {
        VStack(spacing: KimaSpacing.sm) {
            VStack(spacing: KimaSpacing.sm) {
                // The results list floats over the map under the search pill (as on the web), so the
                // chips and the rail below never move. It is drawn behind the top row so its fade never
                // covers the buttons.
                overlayControls
                    .background(alignment: .top) { searchResults }
                    .zIndex(1)

                if case .loaded(let tracks) = vm.phase, !tracks.isEmpty, !vm.legendEntries.isEmpty {
                    let hidden = vm.searchListShown || vm.selectedTrackId != nil || panelLifted
                    VibeMoodLegend(
                        entries: vm.legendEntries, pinned: vm.legendPinned, trackCount: tracks.count,
                        onToggle: { key in withAnimation(.easeInOut(duration: 0.2)) { vm.toggleLegend(key) } })
                    // Hidden in place while the search list or a panel over the keyboard covers it, or a star
                    // is selected (more open map), so nothing below moves.
                    .opacity(hidden ? 0 : 1)
                    .allowsHitTesting(!hidden)
                    .accessibilityHidden(hidden)
                    .animation(.easeInOut(duration: 0.2), value: hidden)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { hudBottom = $0 }

            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Map

    private func mapField(tracks: [VibeMapTrack]) -> some View {
        let queueIds = player.queue.map(\.id)
        let showingSimilar = !vm.similarIds.isEmpty
        let source = showingSimilar
            ? vm.similarIds.first
            : vm.operationSourceId.flatMap { queueIds.contains($0) ? $0 : nil }
        let kind = vm.operationKind(queueOrigin: player.queueOrigin)
        return VibeMapField(
            tracks: tracks, mapKey: vm.mapKey ?? "", mapGeneration: vm.mapGeneration,
            highlightedIds: vm.highlightedIds,
            operationSourceId: source, operationKind: kind, focusMood: vm.legendPinned,
            selectedId: vm.selectedTrackId,
            pathStartId: vm.pathStartMark, pathEndId: vm.pathEndMark,
            leader: vm.panel == nil && !vm.searchListShown
                ? readoutFrame.map { VibeLeaderTarget(readout: $0, rail: railFrame) } : nil,
            labelBand: VibeLabelBand(top: VibeLabelBand.top(hudBottom: hudBottom, searchListBottom: searchListBottom),
                                     bottom: bottomStackTop - KimaSpacing.xl, rail: railFrame),
            playingId: player.currentTrack?.id, queueIds: queueIds,
            locateTrigger: locateTrigger, homeTrigger: homeTrigger,
            flyTrigger: vm.flyTrigger, flyToId: vm.flyToId,
            onTap: { id in
                if id != nil { closeHelp() }
                vm.handleTap(id)
            },
            onDoubleTap: { id in Task { await vm.play(trackId: id, client: env.client, player: player) } },
            onLongPress: { id in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                closeHelp()
                vm.handleTap(id)
            })
    }

    // MARK: - Phase views

    private var loadingContent: some View {
        KimaLoadingState(text: vm.isComputing ? "building the map" : "loading the map")
            .accessibilityIdentifier("vibe-loading")
    }

    private func failedContent(message: String) -> some View {
        KimaErrorState(message: message) { Task { await vm.load(client: env.client) } }
            .accessibilityIdentifier("vibe-failed")
    }

    private var emptyContent: some View {
        KimaEmptyState(icon: "waveform", title: "no tracks with vibe analysis yet",
                       message: "tracks appear as enrichment finishes")
            .accessibilityIdentifier("vibe-empty")
    }
}
