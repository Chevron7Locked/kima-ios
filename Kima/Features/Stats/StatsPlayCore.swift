import SwiftUI

// MARK: PlayCore — "play those N" under the concentration fact

struct StatsPlayCore: View {
    let count: Int
    let period: StatsPeriod
    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @State private var busy = false

    /// Most tracks the play button plays.
    private static let sliceCap = 100

    var body: some View {
        let willPlay = min(count, Self.sliceCap)
        Button {
            busy = true
            Task {
                defer { busy = false }
                guard let tracks = try? await env.client.getPlayableSlice(of: "core", limit: willPlay, period: period),
                      !tracks.isEmpty else { return }
                player.play(tracks: tracks)
            }
        } label: {
            let label = willPlay < count ? "play the top \(willPlay)" : "play these \(count)"
            Group {
                if busy {
                    HStack(spacing: KimaSpacing.sm) { ProgressView().controlSize(.small); Text(label) }
                } else {
                    Label(label, systemImage: "play.fill")
                }
            }
            .font(KimaType.headline)
            .foregroundStyle(KimaColor.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("play-core")
        .disabled(busy)
    }
}
