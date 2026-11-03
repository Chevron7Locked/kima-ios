import SwiftUI
import UIKit

// MARK: - PlayerTransportControls

/// All playback controls below the seek bar: transport row (Shuffle, Previous, Play/Pause,
/// Next, Repeat), skip row (30 s back/forward), and a secondary cluster (SleepTimer, Lyrics,
/// Vibe in a triangle; a flat row when vibe embeddings are unavailable). Active shuffle/repeat
/// use amber, an intentional divergence from the web's purple.
struct PlayerTransportControls: View {

    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env

    @Binding var showLyrics: Bool
    let sleepTimer: SleepTimerModel

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            transportRow

            // ±30s skip is a long-form (audiobook/podcast) control — for music, prev/next +
            // the scrubber cover it. Restored contextually for long-form; hidden for music.
            secondaryCluster
                .padding(.top, KimaSpacing.lg)
        }
    }

    // MARK: - Transport row

    private var transportRow: some View {
        HStack(alignment: .center, spacing: 0) {
            // for audiobooks, shuffle + next/prev are disabled.
            if player.playbackType.isAudiobook {
                audiobookTransportRow
            } else {
                musicTransportRow
            }
        }
    }

    /// Music transport: Shuffle · Prev · Play · Next · Repeat
    private var musicTransportRow: some View {
        HStack(alignment: .center, spacing: 0) {
            // Shuffle — amber when active
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(player.isShuffle ? env.accent.color : KimaColor.textMuted)
                    .opacity(player.queuePlaysInOrder ? 0.35 : 1)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(player.queuePlaysInOrder)
            .accessibilityLabel(player.isVibeQueue ? "a vibe queue plays in order"
                                : player.queuePlaysInOrder ? "this station plays in order"
                                : (player.isShuffle ? "shuffle on" : "shuffle off"))

            // Previous — greyed out at the top of a non-repeating queue, where the app
            // has nowhere to go back to. Un-greys 3 s in, when it means "restart this track".
            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(KimaColor.textPrimary)
                    .kimaDisabled()
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!player.canGoPrevious)
            .accessibilityLabel("previous")

            // Play / Pause
            playPauseButton

            // Next — greyed out on the last track of a non-repeating queue, where the app
            // has nowhere to go forward to. Any repeat mode gives it a wrap, so it lights up.
            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(KimaColor.textPrimary)
                    .kimaDisabled()
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!player.canGoNext)
            .accessibilityLabel("next")

            // Repeat
            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(
                        player.repeatMode == .off ? KimaColor.textMuted : env.accent.color
                    )
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("repeat: \(player.repeatMode.rawValue)")
        }
    }

    /// Audiobook transport: [spacer] · Play/Pause · [spacer]
    /// Shuffle and next/previous are disabled for audiobooks.
    private var audiobookTransportRow: some View {
        HStack(alignment: .center, spacing: 0) {
            Spacer()
            playPauseButton
            Spacer()
        }
    }

    private var playPauseButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            player.togglePlayPause()
        } label: {
            playPauseCircle.frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.isPlaying || player.isWaitingForAudio ? "pause" : "play")
        .accessibilityValue(isWaiting ? "loading" : "")
    }

    // MARK: - Play/Pause circle

    @ViewBuilder
    private var playPauseCircle: some View {
        ZStack {
            // The mini player's tinted-glass disc, scaled up with a little more of the song's colour.
            // Loading / buffering: a spinner in a faint ring, unmistakably not the playing state.
            NowPlayingDisc(tint: playButtonTint, wash: isWaiting ? 0.10 : 0.30)

            if isWaiting {
                ProgressView().controlSize(.large).tint(KimaColor.textPrimary)
            } else {
                Image(systemName: playPauseIcon)
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(KimaColor.textPrimary)
                    .offset(x: player.isPlaying ? 0 : 2)
            }
        }
    }

    private var isWaiting: Bool {
        player.engineStatus == .loading || player.engineStatus == .buffering
    }

    private var playButtonTint: Color {
        if player.engineStatus == .error { return KimaColor.danger }
        return env.accent.color.opacity(isWaiting ? 0.35 : 1.0)
    }

    private var playPauseIcon: String {
        switch player.engineStatus {
        case .error:    return "arrow.clockwise"
        case .blocked:  return "play.fill"
        default: return player.isPlaying ? "pause.fill" : "play.fill"
        }
    }

    // MARK: - Secondary cluster (labeled "setlist" row)

    /// Below-transport secondary controls. Adapts per content type:
    /// - **Music**: Vibe · Lyrics · Sleep (existing "setlist" cluster).
    /// - **Long-form** (audiobook / podcast): ±30 s skip · Speed · Sleep.
    ///   Shuffle and next/prev are already removed from the transport row for audiobooks.
    @ViewBuilder
    private var secondaryCluster: some View {
        let isLongForm = player.playbackType.isLongForm

        VStack(spacing: KimaSpacing.md) {
            // A faint hairline under the transport, on the column's gutter like every other rule.
            KimaHairline()

            if isLongForm {
                longFormSecondaryCluster
            } else {
                musicSecondaryCluster
            }
        }
    }

    /// Music secondary: Vibe · Lyrics · Sleep
    private var musicSecondaryCluster: some View {
        let vibeAvailable = player.vibeEmbeddingsAvailable == true
        let hasTrack = player.currentTrack != nil

        return HStack(spacing: 0) {
            if vibeAvailable && hasTrack {
                PlayerSecondaryButton(
                    icon: "waveform", label: "vibe",
                    active: player.isVibeQueue, loading: player.isVibeLoading
                ) {
                    Task { await player.toggleVibeMode(client: env.client) }
                }
            }
            if hasTrack {
                PlayerSecondaryButton(
                    icon: "music.microphone", label: "lyrics",
                    active: showLyrics
                ) {
                    withAnimation(.easeInOut(duration: 0.20)) { showLyrics.toggle() }
                }
            }
            SleepTimerButton(model: sleepTimer)
                .frame(maxWidth: .infinity)

            AirPlayRoutePicker()
        }
    }

    /// Long-form secondary: back 30 s · forward 30 s · speed · sleep
    private var longFormSecondaryCluster: some View {
        // Four equal columns, the same rhythm as the music row.
        HStack(spacing: 0) {
            LongFormSkipButton(seconds: -30)
            LongFormSkipButton(seconds: 30)

            // Speed picker — amber tint when not 1×
            SpeedPickerButton()
                .frame(maxWidth: .infinity)

            SleepTimerButton(model: sleepTimer)
                .frame(maxWidth: .infinity)
        }
    }
}
