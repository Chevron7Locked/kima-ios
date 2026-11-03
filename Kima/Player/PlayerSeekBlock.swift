import SwiftUI

// MARK: - PlayerSeekBlock

/// Seek-bar block: WaveformScrubber + elapsed/duration labels + engine status hint. Left label is elapsed time
/// (scrub position while dragging); right is total duration for tracks, remaining for long-form (`rightLabel`).
/// `canSeek` and `downloadProgress` let the scrubber show a disabled state and a secondary fill.
struct PlayerSeekBlock: View {

    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env

    @Binding var isScrubbing: Bool
    @Binding var scrubProgress: Double
    let peaks: [Double]

    // MARK: - Body

    var body: some View {
        VStack(spacing: KimaSpacing.xs) {
            WaveformScrubber(
                duration: player.duration,
                displayTime: isScrubbing
                    ? scrubProgress * max(1, player.duration)
                    : player.displayTime,
                isScrubbing: isScrubbing,
                onScrubChanged: { p in
                    isScrubbing = true
                    scrubProgress = p
                },
                onScrubEnded: { p in
                    isScrubbing = false
                    player.seek(to: p * max(1, player.duration))
                },
                peaks: peaks,
                canSeek: player.canSeek,
                downloadProgress: player.downloadProgress,
                accent: env.accent.color,
                accentDeep: env.accent.deep
            )

            // Time labels
            HStack {
                // Elapsed — follows adaptive accent while scrubbing
                Text(elapsedLabel)
                    .font(KimaType.caption.monospacedDigit())
                    .foregroundStyle(isScrubbing ? env.accent.color : KimaColor.textMuted)
                    .animation(.none, value: isScrubbing)

                Spacer()

                // Right label: total duration for music tracks;
                // remaining time (prefixed "-") for long-form (§4.2).
                Text(rightLabel)
                    .font(KimaType.caption.monospacedDigit())
                    .foregroundStyle(KimaColor.textMuted)
            }

            // Engine status row
            engineStatusRow
        }
    }

    // MARK: - Labels

    private var elapsedLabel: String {
        let t = isScrubbing
            ? scrubProgress * max(1, player.duration)
            : player.displayTime
        return t.durationFormatted
    }

    private var rightLabel: String {
        if player.playbackType.isLongForm {
            // Long-form: show remaining time prefixed with "−"
            let currentT = isScrubbing
                ? scrubProgress * max(1, player.duration)
                : player.displayTime
            let remaining = max(0, player.duration - currentT)
            return "−\(remaining.durationFormatted)"
        }
        return player.duration.durationFormatted
    }

    // MARK: - Engine status hint

    @ViewBuilder
    private var engineStatusRow: some View {
        switch player.engineStatus {
        case .buffering:
            HStack(spacing: KimaSpacing.xs) {
                ProgressView()
                    .scaleEffect(0.65)
                    .tint(KimaColor.textMuted)
                Text("buffering…")
                    .font(KimaType.meta)
                    .foregroundStyle(KimaColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 18)

        case .blocked:
            Text("tap play to resume")
                .font(KimaType.meta)
                .foregroundStyle(env.accent.color)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 18)

        case .error:
            Text(player.audioError ?? "playback error — tap to retry")
                .font(KimaType.meta)
                .foregroundStyle(KimaColor.danger.opacity(0.75))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 18)

        default:
            Color.clear.frame(height: 18)
        }
    }
}
