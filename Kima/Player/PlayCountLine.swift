import SwiftUI

/// Session cache of completed-listen counts per track. Never invalidated, so a count
/// does not renumber mid-song (web parity with `useTrackPlays`).
@MainActor enum PlayCountStore { static var counts: [String: Int] = [:] }

/// "45th play" under the artist in the full player. Shows nothing for a first listen.
struct PlayCountLine: View {
    let trackId: String?
    let onOpen: () -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var fetched: (id: String, plays: Int)?

    private var heardBefore: Int? {
        guard let id = trackId else { return nil }
        if let cached = PlayCountStore.counts[id] { return cached }
        if let fetched, fetched.id == id { return fetched.plays }
        return nil
    }

    var body: some View {
        Group {
            if let heardBefore, heardBefore >= 1 {
                Button(action: onOpen) {
                    Text("\(PlayCountOrdinal.string(heardBefore + 1)) play")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityHint("open stats")
                .accessibilityIdentifier("play-count-line")
            } else {
                EmptyView()
            }
        }
        .task(id: trackId) {
            guard let id = trackId, PlayCountStore.counts[id] == nil else { return }
            guard let n = try? await env.client.getTrackPlayCount(trackId: id),
                  !Task.isCancelled else { return }
            PlayCountStore.counts[id] = n
            fetched = (id, n)
        }
    }
}
