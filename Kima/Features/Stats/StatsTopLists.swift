import SwiftUI

// MARK: Most played

struct StatsTopLists: View {
    let l: ListeningStats
    let period: StatsPeriod
    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @State private var busyTrack: String?

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            StatsFinding(claim: "most played")
            VStack(alignment: .leading, spacing: KimaSpacing.xxl) {
                ranked(label: "artists",
                       rows: l.topArtists.map { ($0.name, "", $0.plays, $0.id) },
                       idPrefix: "top-artist", busyId: nil,
                       onTap: { id in
                           env.router.selectedTab = .library
                           env.router.pendingLibraryRoute = .artist(id: id)
                       })
                ranked(label: "tracks",
                       rows: l.topTracks.map { ($0.title, $0.artist, $0.plays, $0.id) },
                       idPrefix: "top-track", busyId: busyTrack,
                       onTap: { id in playSlice(startingAt: id) })
            }
        }
    }

    /// Tracks play the window the list was drawn from (web usePlaySlice: the
    /// press plays the slice, not one track alone); artists go to their page.
    private func playSlice(startingAt id: String) {
        let ids = l.topTracks.map(\.id)
        let idx = max(0, ids.firstIndex(of: id) ?? 0)
        busyTrack = id
        Task {
            defer { busyTrack = nil }
            do {
                let tracks = try await env.client.getPlayableSlice(of: "top",
                                                                   limit: max(ids.count, 1),
                                                                   period: period)
                if tracks.isEmpty { return }
                player.play(tracks: tracks, startAt: min(idx, tracks.count - 1))
            } catch {
                // A failed press is not worth a dialogue on a page about music (web parity).
            }
        }
    }

    private func ranked(label: String, rows: [(String, String, Int, String)], idPrefix: String, busyId: String?, onTap: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            Text(label)
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                Button { onTap(row.3) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.md) {
                        Text("\(i + 1)")
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textFaint)
                            .frame(width: 16, alignment: .trailing)
                        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                            Text(row.0.lowercased())
                                .font(i == 0 ? KimaType.headline : KimaType.body)
                                .foregroundStyle(KimaColor.textPrimary)
                                .lineLimit(1)
                            if !row.1.isEmpty {
                                Text(row.1.lowercased())
                                    .font(KimaType.caption)
                                    .foregroundStyle(KimaColor.textMuted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: KimaSpacing.md)
                        if busyId == row.3 {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(row.2.formatted(.number))
                                .font(KimaType.caption)
                                .foregroundStyle(KimaColor.textSecondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, KimaSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busyId != nil)
                .accessibilityIdentifier("\(idPrefix)-\(i)")
                .accessibilityLabel(idPrefix == "top-track" ? "play \(row.0.lowercased())" : row.0.lowercased())
            }
        }
    }
}
