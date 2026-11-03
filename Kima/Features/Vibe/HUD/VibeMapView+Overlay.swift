import SwiftUI

// MARK: - VibeMapView overlay extensions
//
// Top bar, tool rail, readout, panels and mini player, split from VibeMapView.swift to keep that file
// under the 350-line budget.

extension VibeMapView {

    // MARK: - Helpers

    /// The map has loaded with at least one track.
    private var hasMap: Bool {
        if case .loaded(let tracks) = vm.phase { return !tracks.isEmpty }
        return false
    }

    /// Whether the currently playing track is on the loaded map.
    private var nowPlayingIsOnMap: Bool {
        guard let id = player.currentTrack?.id,
              case .loaded(let tracks) = vm.phase else { return false }
        return tracks.contains(where: { $0.id == id })
    }

    // MARK: - Overlay controls (top bar)

    /// Height of the top row: the 44pt buttons plus the padding above and below.
    static let controlsHeight: CGFloat = KimaLayout.chromeDiscSize + KimaSpacing.sm * 2

    /// Room the bottom stack leaves for the top row, the mood chips and the track count.
    static let topReserve: CGFloat = controlsHeight + 44 + 16 + KimaSpacing.sm * 3

    /// Top row: close, the search box, the labels switch, "show whole library" and (only when the
    /// playing track is on the map) "find playing track". Glass discs, like the app's corner buttons.
    var overlayControls: some View {
        HStack(alignment: .center, spacing: KimaSpacing.sm) {
            chromeButton("xmark", label: "close", id: "vibe-close") { onClose() }
            // The field's own "done" is the one way out named "done"; the keyboard keeps a plain return.
            KimaSearchField(prompt: "find a track or artist", submitLabel: .return, text: $vm.searchQuery)
                .accessibilityIdentifier("vibe-search")
            labelsButton
            chromeButton("arrow.up.left.and.down.right.magnifyingglass", label: "show whole library", id: "vibe-home") {
                homeTrigger += 1
            }
            if nowPlayingIsOnMap {
                chromeButton("scope", label: "find playing track", id: "vibe-locate") { locateTrigger += 1 }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: nowPlayingIsOnMap)
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.sm)
    }

    /// An open panel rides above the keyboard, up to the top row; the chips hide under it.
    var panelLifted: Bool { vm.panel != nil && keyboardHeight > 0 }

    /// Search results under the top row, left of the rail, hanging over the map on a dark fade that
    /// also runs up behind the top row; hidden after a pick until the text changes. With the keyboard
    /// up the list ends above it.
    @ViewBuilder
    var searchResults: some View {
        if vm.searchListShown {
            VibeSearchResults(matches: vm.searchMatches, albumTitles: vm.albumTitles,
                              bottomLimit: keyboardHeight > 0 ? screenHeight - keyboardHeight : nil) { track in
                // Keyboard down, so the picked track's readout and the rail are in view.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                closeHelp()
                vm.selectSearchResult(track.id)
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { searchListBottom = $0 }
            .onDisappear { searchListBottom = nil }
            .padding(.trailing, Self.railInset)
            .padding(.top, Self.controlsHeight)
            .background {
                VibeFadeBackdrop(openEdge: .bottom, fade: 64)
                    .padding(.bottom, -64)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }

    /// One top-bar button: a 16pt semibold glyph on the app's glass chrome disc.
    private func chromeButton(_ symbol: String, label: String, id: String,
                              action: @escaping () -> Void) -> some View {
        KimaChromeButton(symbol: symbol, label: label, id: id, cardStyle: true, action: action)
    }

    /// The labels switch. On: a filled tag on the glass disc. Off: an outline tag in a bare outline
    /// ring. Both at full strength, so off reads as a setting, not as a disabled button.
    private var labelsButton: some View {
        Button { showLabels.toggle() } label: {
            let glyph = Image(systemName: showLabels ? "tag.fill" : "tag")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KimaColor.textPrimary)
            if showLabels {
                glyph.kimaChromeDisc()
            } else {
                glyph.kimaOutlineRing().contentShape(Rectangle())
            }
        }
        .buttonStyle(.kimaCard)
        .accessibilityLabel(showLabels ? "hide labels" : "show labels")
        .accessibilityIdentifier("vibe-labels")
    }

    // MARK: - Tool rail

    /// Width of the rail's column at the right edge.
    static let railColumn: CGFloat = 64

    /// Room the readout and the panels leave on their right for the rail and a gap before it.
    static let railInset: CGFloat = KimaSpacing.lg + railColumn + KimaSpacing.md

    /// The rail's bottom edge above the home indicator: clear of the mini player's card whether or not
    /// it shows, so the rail sits in the same place in every state.
    static let railLift: CGFloat = MiniPlayerLayout.cardGap + MiniPlayerLayout.cardHeight + KimaSpacing.md

    /// Right edge, pinned `railLift` above the home indicator. Song path and blend sit lowest, nearest
    /// the thumb, then help; back sits on top while there is something to undo, so it never moves the
    /// others. Help keeps its place while the help list is open. Song path and blend start from the
    /// selected star.
    var toolRail: some View {
        VStack(spacing: KimaSpacing.md) {
            if let back {
                VibeInstrumentButton(symbol: "arrow.uturn.backward", label: back.label, id: "vibe-clear",
                                     spokenLabel: back.spoken) {
                    withAnimation(.easeInOut(duration: 0.2)) { back.run() }
                }
                .transition(.opacity)
            }
            VibeInstrumentButton(symbol: "questionmark", label: "help", id: "vibe-help") {
                withAnimation(.easeInOut(duration: 0.2)) { helpOpen = true }
            }
            .opacity(helpOpen ? 0 : 1)
            .allowsHitTesting(!helpOpen)
            .accessibilityHidden(helpOpen)
            VibeInstrumentButton(symbol: "point.topleft.down.to.point.bottomright.curvepath", label: "song path",
                                 id: "vibe-rail-songpath", on: vm.panel == .songPath) { toggleTool(.songPath) }
            VibeInstrumentButton(symbol: "arrow.triangle.merge", label: "blend",
                                 id: "vibe-rail-blend", on: vm.panel == .blend) { toggleTool(.blend) }
        }
        .frame(width: Self.railColumn)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { railFrame = $0 }
    }

    /// The back button's words, what VoiceOver says and what a tap does: the help list closes first,
    /// then the most recent thing on the map steps back. Nil hides the button.
    private var back: (label: String, spoken: String, run: () -> Void)? {
        if helpOpen { return ("close", "close help", { closeHelp() }) }
        guard let step = vm.nextStepBack else { return nil }
        return (step.railLabel, vm.stepBackSpokenLabel ?? step.railLabel, { vm.stepBack() })
    }

    private func toggleTool(_ tool: VibePanel) {
        closeHelp()
        withAnimation(.easeInOut(duration: 0.2)) { vm.toggleTool(tool) }
    }

    /// Hides the help list and remembers it was seen (a star, a search pick or a tool shows what it
    /// would cover).
    func closeHelp() {
        guard helpOpen else { return }
        withAnimation(.easeInOut(duration: 0.2)) { helpOpen = false }
        helpSeen = true
    }

    /// The open panel, low on the screen for one-handed use.
    @ViewBuilder
    var panelView: some View {
        switch vm.panel {
        case .songPath:
            VibeSongPathPanel(vm: vm).transition(.move(edge: .bottom).combined(with: .opacity))
        case .blend:
            VibeBlendPanel(vm: vm).transition(.move(edge: .bottom).combined(with: .opacity))
        case nil:
            EmptyView()
        }
    }

    // MARK: - Readout

    /// What the bottom stack shows: the help list, the open panel or the selected track.
    private var bottomContent: VibeReadout.Content {
        guard hasMap else { return .none }
        return VibeReadout.content(helpOpen: helpOpen, panelOpen: vm.panel != nil,
                                   hasSelection: vm.selectedTrackId.flatMap { vm.trackFor(id: $0) } != nil)
    }

    /// The selected track and its actions, above the mini player and left of the rail.
    @ViewBuilder
    var readout: some View {
        if let selected = vm.selectedTrackId.flatMap({ vm.trackFor(id: $0) }) {
            VibeReadoutView(
                track: selected,
                isPlayLoading: vm.isPlayLoading, playError: vm.playError,
                onPlay: { Task { await vm.play(trackId: selected.id, client: env.client, player: player) } },
                onPlaySimilar: { vm.launch { await vm.startPlaySimilar(trackId: selected.id, client: env.client, player: player) } },
                onSimilar: { Task { await vm.showSimilar(trackId: selected.id, client: env.client) } },
                onMoreLike: { withAnimation(.easeInOut(duration: 0.2)) { vm.addToBlend(selected.id, column: .more) } },
                onLessLike: { withAnimation(.easeInOut(duration: 0.2)) { vm.addToBlend(selected.id, column: .less) } },
                onOpenArtist: { viewArtistId = selected.artistId },
                onOpenAlbum: { viewAlbumId = selected.albumId },
                onFrameChange: { readoutFrame = $0 })
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: vm.selectedTrackId)
        }
    }

    // MARK: - Bottom overlay

    /// The help list, the open panel or the readout above the mini player, left of the rail, on one dark
    /// fade that runs beneath the rail. The rail stays pinned and fades out while the keyboard covers its place;
    /// with the keyboard up an open panel rides above it, may grow up to the top row, and the mini player
    /// steps aside.
    @ViewBuilder
    var bottomOverlay: some View {
        let lifted = panelLifted
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: KimaSpacing.md) {
                Spacer(minLength: lifted ? Self.controlsHeight + KimaSpacing.md : Self.topReserve)
                VStack(spacing: KimaSpacing.md) {
                    Group {
                        switch bottomContent {
                        case .help:
                            VibeHelpView()
                                .transition(.opacity)
                        case .panel: panelView
                        case .track: readout
                        case .none: EmptyView()
                        }
                    }
                    .padding(.trailing, Self.railInset)
                    if !lifted { miniPlayer }
                }
                .layoutPriority(1)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { bottomStackTop = $0 }
                .background(alignment: .top) {
                    if bottomContent != .none {
                        // Lifted, the panel reaches the top row; its fade stays in the gap below it.
                        let fade = lifted ? KimaSpacing.md : 96
                        VibeFadeBackdrop(fade: fade)
                            .padding(.top, -fade)
                            .padding(.bottom, -(safeAreaBottom * 2 + MiniPlayerLayout.cardGap))
                    }
                }
            }
            // fullScreenCover has no tab bar — use safeArea + gap only, not tabBarHeight.
            .padding(.bottom, lifted ? max(keyboardHeight - safeAreaBottom, 0) + KimaSpacing.sm
                                     : safeAreaBottom + MiniPlayerLayout.cardGap)

            if hasMap {
                toolRail
                    .padding(.trailing, KimaSpacing.lg)
                    .padding(.bottom, safeAreaBottom + Self.railLift)
                    .opacity(keyboardHeight > 0 ? 0 : 1)
                    .allowsHitTesting(keyboardHeight == 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: swipeState.isMinimized)
        .animation(.easeOut(duration: 0.25), value: lifted)
        .animation(.easeOut(duration: 0.2), value: keyboardHeight > 0)
        .ignoresSafeArea(.keyboard)
    }

    /// Mini player — the same Kima card and swipe state as AppShellView.
    @ViewBuilder
    private var miniPlayer: some View {
        if player.currentTrack != nil, !swipeState.isDismissed {
            if swipeState.isMinimized {
                HStack {
                    Spacer()
                    MiniPlayerEdgeTab(swipeState: swipeState)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                MiniPlayerBar(swipeState: swipeState, onExpand: { showFullPlayer = true })
                    .padding(.horizontal, MiniPlayerLayout.horizontalInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
