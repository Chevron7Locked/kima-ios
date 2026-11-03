import SwiftUI

// MARK: - QueueEndRow

/// The last row of a queue with nothing after the current song: says playback stops there and
/// offers play similar, which queues the current song's closest matches.
struct QueueEndRow: View {
    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: KimaSpacing.md) {
            Text("nothing after this")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
            Spacer(minLength: KimaSpacing.sm)
            if !player.isVibeQueue {
                Button {
                    Task { await player.toggleVibeMode(client: env.client) }
                } label: {
                    HStack(spacing: KimaSpacing.xs) {
                        if player.isVibeLoading {
                            ProgressView().scaleEffect(0.7).tint(KimaColor.textMuted)
                        } else {
                            Image(systemName: "waveform")
                        }
                        Text("play similar")
                    }
                    .font(KimaType.captionStrong)
                    .foregroundStyle(KimaColor.textPrimary)
                    .padding(.horizontal, KimaSpacing.md)
                    .padding(.vertical, KimaSpacing.sm)
                    .overlay(Capsule().strokeBorder(KimaColor.hairline, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(player.isVibeLoading)
                .accessibilityIdentifier("queue-play-similar")
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.sm)
        .overlay(alignment: .bottomLeading) {
            if let error = player.vibeError {
                Text(error)
                    .font(KimaType.meta)
                    .foregroundStyle(KimaColor.danger)
                    .padding(.horizontal, KimaSpacing.lg)
                    .offset(y: 14)
            }
        }
        .padding(.bottom, KimaSpacing.lg)
        .accessibilityIdentifier("queue-end-row")
    }
}

// MARK: - QueueSectionLabel

/// A small muted label row in the queue list, e.g. "played" above the songs already heard.
struct QueueSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(KimaType.meta)
            .tracking(0.8)
            .foregroundStyle(KimaColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.top, KimaSpacing.md)
            .padding(.bottom, KimaSpacing.xs)
    }
}
