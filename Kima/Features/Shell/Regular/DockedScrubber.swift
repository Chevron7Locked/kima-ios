import SwiftUI

// MARK: - DockedScrubber

/// The docked bar's seek line: elapsed time, a thin bar you drag to seek, total time. The position follows
/// the finger while dragging and is sent to the player on release. Disabled (no drag, dimmed) while the
/// stream cannot seek.
struct DockedScrubber: View {
    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env

    @State private var scrub: Double?

    private var duration: Double { max(1, player.duration) }
    private var progress: Double {
        scrub ?? (player.duration > 0 ? min(1, max(0, player.displayTime / player.duration)) : 0)
    }

    var body: some View {
        HStack(spacing: KimaSpacing.sm) {
            Text((progress * player.duration).durationFormatted)
                .frame(minWidth: 36, alignment: .trailing)
                .foregroundStyle(scrub == nil ? KimaColor.textMuted : env.accent.color)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(KimaColor.hairline)
                    // Scaled, not re-measured, so a time tick never triggers a layout pass.
                    Capsule().fill(env.accent.color)
                        .scaleEffect(x: progress, y: 1, anchor: .leading)
                    Circle().fill(KimaColor.textPrimary)
                        .frame(width: 10, height: 10)
                        .offset(x: geo.size.width * progress - 5)
                        .opacity(scrub == nil ? 0 : 1)
                }
                .frame(height: scrub == nil ? 3 : 5)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { scrub = min(1, max(0, $0.location.x / max(1, geo.size.width))) }
                        .onEnded { _ in
                            if let scrub { player.seek(to: scrub * duration) }
                            scrub = nil
                        }
                )
            }
            .frame(height: KimaLayout.minTouchTarget)
            Text(player.duration.durationFormatted)
                .frame(minWidth: 36, alignment: .leading)
                .foregroundStyle(KimaColor.textMuted)
        }
        .font(KimaType.meta.monospacedDigit())
        .disabled(!player.canSeek)
        .opacity(player.canSeek ? 1 : 0.5)
        .animation(.easeOut(duration: 0.15), value: scrub == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("position")
        .accessibilityValue("\(player.displayTime.durationFormatted) of \(player.duration.durationFormatted)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.seek(to: min(player.duration, player.displayTime + 15))
            case .decrement: player.seek(to: max(0, player.displayTime - 15))
            @unknown default: break
            }
        }
    }
}
