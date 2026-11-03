import SwiftUI
import UIKit

// MARK: - NowPlayingPlayButton

/// Play / pause disc shared by the iPhone mini player and the iPad docked bar: the tinted-glass disc, a retry
/// glyph after a playback error, a spinner while buffering. 40pt drawn, 44pt tappable.
struct NowPlayingPlayButton: View {
    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env

    var size: CGFloat = 40

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            player.togglePlayPause()
        } label: {
            ZStack {
                NowPlayingDisc(tint: tint, wash: 0.14)
                icon.frame(width: 20, height: 20)
            }
            .frame(width: size, height: size)
            .kimaHitTarget(growsLayout: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11yLabel)
    }

    private var tint: Color {
        if player.audioError != nil { return KimaColor.danger }
        // A faint ring while buffering, so the spinner state never reads as playing.
        if player.isBuffering       { return env.accent.color.opacity(0.35) }
        return env.accent.color
    }

    /// Ink glyph on the dark disc.
    @ViewBuilder
    private var icon: some View {
        let fg = KimaColor.textPrimary
        if player.audioError != nil {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(fg)
        } else if player.isBuffering {
            ProgressView().controlSize(.small).tint(fg)
        } else if player.isPlaying {
            Image(systemName: "pause.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(fg)
        } else {
            Image(systemName: "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(fg)
                .offset(x: 1.5)   // optical centering for the play triangle
        }
    }

    private var a11yLabel: String {
        if player.audioError != nil { return "retry playback" }
        if player.isBuffering       { return "buffering" }
        return player.isPlaying ? "pause" : "play"
    }
}

// MARK: - NowPlayingDisc

/// The disc behind a now-playing play / pause: dark glass with a soft wash of the song's colour and a ring in
/// that colour, so the page's amber play button stays the one loud control. Draw an ink glyph on it.
struct NowPlayingDisc: View {
    let tint: Color
    /// Opacity of the song-colour wash over the glass.
    let wash: Double

    var body: some View {
        Circle()
            .fill(KimaColor.discGlass)
            .overlay(Circle().fill(tint.opacity(wash)))
            .overlay(Circle().strokeBorder(tint, lineWidth: 1.5))
    }
}

// MARK: - NowPlayingVibeButton

/// Play similar on/off, beside play / pause on the mini player and the docked bar. Hidden until the server says
/// the vibe engine is installed, and for long-form playback.
struct NowPlayingVibeButton: View {
    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    var body: some View {
        if player.vibeEmbeddingsAvailable == true, player.currentTrack != nil {
            let on = player.isVibeQueue
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task {
                    await player.toggleVibeMode(client: env.client)
                    showVibeResult()
                }
            } label: {
                ZStack {
                    if player.isVibeLoading {
                        ProgressView().tint(env.accent.color).scaleEffect(0.75)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(on ? env.accent.color : KimaColor.textSecondary)
                    }
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(player.isVibeLoading)
            .accessibilityLabel(on ? "vibe, on" : "vibe")
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("mini-vibe")
        }
    }

    /// Toasts what this button just did. Only the button's own tap reads the message, so a toast
    /// raised later from the full player is not shown twice.
    private func showVibeResult() {
        if let error = player.vibeError {
            toast.show(error, style: .error)
            player.vibeError = nil
        } else if let notice = player.vibeNotice {
            toast.show(notice, style: .success)
            player.vibeNotice = nil
        }
    }
}
