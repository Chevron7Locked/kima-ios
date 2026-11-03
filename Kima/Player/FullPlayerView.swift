import SwiftUI

// MARK: - FullPlayerView

/// Full-screen Now Playing overlay: a thin composition layer over PlayerArtworkView,
/// PlayerSeekBlock, PlayerTransportControls, SleepTimerSheet and LyricsPanel. Gestures owned
/// here: swipe DOWN on non-interactive areas dismisses (160 pt); the seek scrub is a
/// highPriorityGesture in WaveformScrubber so it wins over the dismiss drag.
struct FullPlayerView: View {

    // Internal (not private): the +Navigation extension uses them.
    @Environment(PlaybackController.self) var player
    @Environment(AppEnvironment.self) var env
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.dismiss) var dismiss   // internal: used by +Dismiss.swift extension
    @Environment(\.horizontalSizeClass) private var sizeClass

    // MARK: - State

    @State private var showQueue = false
    @State private var showLyrics = false

    /// kima://sleep-timer delivery inside the player (the deep-link path on the shared
    /// SleepTimerModel; the button's tap path keeps its own local sheet state).
    private var sleepSheet: Binding<Bool> {
        Binding(get: { player.sleepTimer.showSheet }, set: { player.sleepTimer.showSheet = $0 })
    }

    // Dismiss-swipe
    @State var dismissDelta: CGFloat = 0
    let dismissThreshold: CGFloat = 160

    // Scrub state (flows as Bindings into PlayerSeekBlock)
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    // Waveform peaks — populated from cache or network; reset on track change.
    @State private var peaks: [Double] = []

    // MARK: - Player deep-link delivery (kima://queue · kima://sleep-timer)

    /// Consume a latched PlayerRoute while the full player is up (AppShellView defers
    /// to this side whenever showFullPlayer is true — the two consumers are exclusive).
    private func deliverRouteInPlayer() {
        guard let route = PlayerRouteRouter.shared.take() else { return }
        switch route {
        case .queue:      showQueue = true
        case .sleepTimer: player.sleepTimer.showSheet = true
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let layout = FullPlayerLayout(size: geo.size, isRegular: sizeClass == .regular)
            Group {
                if layout.sideBySide {
                    sideBySideContent(layout)
                } else if layout.controlsWidth > 0 {
                    centredContent(layout)
                } else {
                    // Cap the content column to 720; the outer frame(width:) stays geo.size.width
                    // so the dismiss-drag offset still covers the full screen on iPad.
                    playerContent(artworkSide: layout.artworkSide)
                        .kimaReadableWidth()
                }
            }
            .frame(width: geo.size.width)
            .offset(y: max(0, dismissDelta))
            .opacity(Double(max(0, 1.0 - dismissDelta / 360.0)))
        }
        // Ambient background: the song's colour glow and the collection as a monochrome constellation.
        .background {
            ZStack {
                KimaColor.base
                PlayerAccentGlow()
                VibeConstellation(tracks: constellationTracks, mapKey: env.vibeMapViewModel.mapKey)
            }
            .ignoresSafeArea()
        }
        // Toasts render above this cover: the app-level overlay sits behind any .fullScreenCover.
        // Same ToastCenter, and it is not hit-testable, so it blocks no taps.
        .overlay { KimaToastOverlay() }
        .gesture(dismissDragGesture)
        .vibeReplaceDialog(player: player)
        #if DEBUG
        .debugVibeReplaceMarker(player: player, id: "vibe-fake-replace-origin")
        #endif
        .queueSheet(isPresented: $showQueue, env: env, toastCenter: toastCenter)
        .sleepTimerRouteSheet(isPresented: sleepSheet, model: player.sleepTimer, onColour: env.accent.color)
        .onAppear { deliverRouteInPlayer() }
        .onChange(of: PlayerRouteRouter.shared.pending) { _, _ in deliverRouteInPlayer() }
        .onChange(of: player.currentTrack?.id) { _, newID in
            showLyrics = false   // reset lyrics panel on track change
            // Only dismiss when both the music track is gone AND we are not playing long-form
            // (audiobooks/podcasts have currentTrack == nil on purpose; don't dismiss then).
            if newID == nil && !player.playbackType.isLongForm { dismiss() }
        }
        // Vibe toast forwarding — keeps PlaybackController (Core) decoupled from DesignSystem.
        // The controller sets vibeError / vibeNotice; the view bridges them to ToastCenter.
        .onChange(of: player.vibeError) { _, error in
            guard let error else { return }
            toastCenter.show(error, style: .error)
            player.vibeError = nil
        }
        .onChange(of: player.vibeNotice) { _, notice in
            guard let notice else { return }
            toastCenter.show(notice, style: .success)
            player.vibeNotice = nil
        }
        // Waveform peaks for the track. Re-asked when the stream loads, so a failed or empty answer
        // (never cached) is retried when the track starts playing.
        .task(id: "\(player.currentTrack?.id ?? "")|\(player.canSeek)") {
            guard let trackId = player.currentTrack?.id else { peaks = []; return }
            // Cache hit — no network round-trip, no flash on reopen.
            if let cached = player.waveformCache[trackId] { peaks = cached; return }
            peaks = []
            guard let fetched = try? await env.client.getWaveform(trackId: trackId), !fetched.isEmpty else { return }
            player.waveformCache[trackId] = fetched
            peaks = fetched
        }
        .task {
            // Re-check vibe availability each time the player opens (throttled to once a minute).
            await player.checkVibeAvailability(client: env.client)
        }
        .task {
            // Load the vibe map once so the constellation backdrop has data. Cached after the
            // first fetch (shared VibeMapViewModel on AppEnvironment); no-op if already loaded.
            if case .loading = env.vibeMapViewModel.phase {
                await env.vibeMapViewModel.load(client: env.client)
            }
        }
    }

    /// Snapshot of the vibe-map tracks for the constellation backdrop; empty until loaded.
    private var constellationTracks: [VibeMapTrack] {
        if case .loaded(let tracks) = env.vibeMapViewModel.phase { return tracks }
        return []
    }

    // MARK: - Content column

    /// One column: top bar, cover, then the controls (iPhone and narrow windows).
    private func playerContent(artworkSide: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            topBar
                .padding(.top, KimaSpacing.lg)

            PlayerArtworkView(showLyrics: $showLyrics, maxSide: artworkSide)
                .padding(.top, KimaSpacing.xl)

            trackInfoBlock()
                .padding(.top, KimaSpacing.lg)

            controlsBlock

            Spacer(minLength: KimaSpacing.xl)
        }
        .padding(.horizontal, KimaSpacing.lg)
    }

    /// iPad landscape: the cover (or lyrics) on the left, the title and controls beside it.
    private func sideBySideContent(_ layout: FullPlayerLayout) -> some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, KimaSpacing.lg)
                .padding(.horizontal, KimaSpacing.lg)

            Spacer(minLength: KimaSpacing.lg)

            HStack(alignment: .center, spacing: FullPlayerLayout.columnGap) {
                PlayerArtworkView(showLyrics: $showLyrics, maxSide: layout.artworkSide)
                    .frame(width: layout.artworkSide)

                VStack(alignment: .leading, spacing: 0) {
                    trackInfoBlock()
                    controlsBlock
                }
                .frame(width: layout.controlsWidth)
            }

            Spacer(minLength: KimaSpacing.lg)
        }
    }

    /// iPad portrait: the cover and a capped controls column, centred together in the height under the top bar,
    /// with the title a step larger.
    private func centredContent(_ layout: FullPlayerLayout) -> some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, KimaSpacing.lg)
                .padding(.horizontal, KimaSpacing.lg)

            Spacer(minLength: KimaSpacing.lg)

            PlayerArtworkView(showLyrics: $showLyrics, maxSide: layout.artworkSide)
                .frame(width: layout.artworkSide)

            VStack(alignment: .leading, spacing: 0) {
                trackInfoBlock(titleFont: KimaType.hero)
                controlsBlock
            }
            .frame(width: layout.controlsWidth)
            .padding(.top, KimaSpacing.xxl)

            Spacer(minLength: KimaSpacing.lg)
        }
    }

    /// Seek line, transport and volume, under the title in every layout.
    private var controlsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlayerSeekBlock(
                isScrubbing: $isScrubbing,
                scrubProgress: $scrubProgress,
                peaks: peaks
            )
            .padding(.top, KimaSpacing.lg)

            PlayerTransportControls(
                showLyrics: $showLyrics,
                sleepTimer: player.sleepTimer
            )
            .padding(.top, KimaSpacing.xl)

            // System-volume control, full column width like the seek bar above it.
            // Mechanics (offscreen MPVolumeView engine, KVO truth): KimaVolumeControl.swift
            KimaVolumeControl()
                .padding(.top, KimaSpacing.md)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(KimaColor.textSecondary)
                    .kimaHitTarget()
            }
            .buttonStyle(.plain)

            Spacer()

            Text("now playing")
                .font(KimaType.meta)
                .foregroundStyle(KimaColor.textMuted)
                .tracking(0.1)

            Spacer()

            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(KimaColor.textSecondary)
                    .kimaHitTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("queue")
            .accessibilityIdentifier("queue-button")

            #if DEBUG
            // DEBUG-only: force a stream-drop failure to exercise the recovery on demand.
            // Pause a track first, then tap — the widget should survive + resume at position.
            // Long-press: a stall instead (the watchdog rebuilds the stream after 15 s).
            Button { player.debugSimulateStreamDrop() } label: {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(KimaColor.caution)
                    .kimaHitTarget()
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("simulate stall") { player.debugSimulateStall() }
            }
            .accessibilityLabel("debug: simulate stream drop")
            .accessibilityIdentifier("debug-stream-drop")
            #endif
        }
    }

    // MARK: - Track info

    /// Title and artist are tappable.
    /// For long-form, metadata comes from `longFormNowPlayingMeta` (title/artist
    /// injected by PlaybackController+LongForm on load).
    private func trackInfoBlock(titleFont: Font = KimaType.pageTitle) -> some View {
        // Resolve title/artist — prefer long-form meta when in that mode.
        let longFormMeta = player.longFormNowPlayingMeta
        let titleText: String = {
            if player.playbackType.isLongForm { return longFormMeta?.title ?? "—" }
            return player.currentTrack?.effectiveTitle ?? "—"
        }()
        let artistText: String? = {
            if player.playbackType.isLongForm { return longFormMeta?.artist }
            return player.currentTrack?.artist?.name
        }()

        return VStack(alignment: .leading, spacing: KimaSpacing.xs) {

            Button { openAlbum() } label: {
                Text(titleText.lowercased())
                    .font(titleFont)
                    .tracking(-0.2)
                    .foregroundStyle(KimaColor.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.none, value: player.currentTrack?.id)
            }
            .buttonStyle(.plain)

            if let artistName = artistText {
                Button { openArtist() } label: {
                    Text(artistName.lowercased())
                        .font(KimaType.body)
                        .tracking(0)
                        .foregroundStyle(KimaColor.textSecondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }

            if !player.playbackType.isLongForm {
                PlayCountLine(trackId: player.currentTrack?.id) { openStats() }
            }

            // Vibe match badge.
            // Music only (long-form doesn't have audio feature vectors yet).
            if !player.playbackType.isLongForm, let score = player.vibeMatchScore {
                PlayerVibeMatchBadge(score: score)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
