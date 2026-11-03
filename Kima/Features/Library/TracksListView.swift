import SwiftUI

/// Paginated tracks list for the Collection screen: header row + LazyVStack of track rows, each led by a
/// dot in its mood colour, env.accent.color active-track highlight, mono duration column.
struct TracksListView: View {
    let phase: LoadPhase<[Track]>
    /// The search typed above the list ("" for none).
    let searchText: String
    let currentTrackId: String?
    let onPlayTrack: (Int, [Track]) -> Void  // (index, full list) → play
    let onRetry: () -> Void

    var body: some View {
        switch phase {
        case .loading:
            TracksSkeletonView()
        case .failed(let msg):
            KimaErrorState(message: msg, onRetry: onRetry)
        case .loaded(let tracks):
            if tracks.isEmpty {
                LibraryEmptyState(icon: "music.note.list", noun: "songs", query: searchText, pageOnly: true)
            } else {
                VStack(spacing: 0) {
                    // Column labels, then hairline-separated rows on the gutter (no boxes).
                    TracksHeaderRow()
                    KimaHairline()

                    KimaPageStack(count: tracks.count) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                            CollectionTrackRow(
                                track: track,
                                isCurrent: currentTrackId == track.id,
                                onPlay: { onPlayTrack(idx, tracks) }
                            )
                            if idx < tracks.count - 1 { KimaHairline() }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Header row

private struct TracksHeaderRow: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        HStack(spacing: KimaSpacing.md) {
            // Over the rows' mood-dot column.
            Color.clear.frame(width: 16, height: 1)
            Text("title")
                .frame(maxWidth: .infinity, alignment: .leading)
            // The album column exists on wide screens only (see CollectionTrackRow).
            if hSizeClass != .compact {
                Text("album")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("time")
                .frame(width: 52, alignment: .trailing)
        }
        .font(KimaType.metaStrong)
        .foregroundStyle(KimaColor.textMuted)
        .tracking(0.1)
        .padding(.vertical, KimaSpacing.sm)
    }
}

// MARK: - CollectionTrackRow

private struct CollectionTrackRow: View {
    let track: Track
    /// This row is the loaded track (playing or paused).
    let isCurrent: Bool
    let onPlay: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// On a phone the album folds into the muted meta line so the title keeps the width.
    private var metaLine: String? {
        let parts = hSizeClass == .compact
            ? [track.artist?.name, track.album?.title]
            : [track.artist?.name]
        let line = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    /// The song's mood colour from the vibe map; nil when it has none.
    private var mood: Color? {
        env.vibeMapViewModel.libraryMoods.trackMood[track.id].map(VibeMoodPalette.mapColor(for:))
    }

    var body: some View {
        Button(action: onPlay) {
            TrackRow(moodColumn: true, mood: mood, artwork: .server(track.album?.coverArt), title: track.effectiveTitle,
                     subtitle: metaLine, albumColumn: hSizeClass != .compact ? track.album?.title : nil,
                     duration: track.duration.durationFormatted,
                     nowPlaying: isCurrent ? (env.player.isPlaying ? .playing : .current) : .none,
                     highlight: env.accent.color)
        }
        .buttonStyle(.plain)
        .libraryItemMenu(
            onPlay: onPlay,
            onPlayNext: {
                announcePlayNext(env.player.playNext(track), in: toast)
            },
            onQueue: {
                announceEnqueue(env.player.enqueue(track: track), in: toast)
            },
            onAddToPlaylist: { env.playlistPicker.present(.tracks([track])) }
        )
        // Drag onto the mini-player → Play Next (library rows are always owned tracks).
        .modifier(TrackDragModifier(track: track, enabled: true))
    }
}

// MARK: - Skeleton

private struct TracksSkeletonView: View {
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<16, id: \.self) { _ in
                HStack(spacing: KimaSpacing.md) {
                    Circle()
                        .fill(KimaColor.surface)
                        .frame(width: 7, height: 7)
                        .frame(width: 16)
                    RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                        .fill(KimaColor.surface)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(KimaColor.surface)
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(KimaColor.surface)
                            .frame(width: 80, height: 10)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(KimaColor.surface)
                        .frame(width: 36, height: 12)
                }
                // Same anatomy as a real row: on the gutter, no box.
                .padding(.vertical, KimaSpacing.sm)
            }
        }
        .kimaSkeletonPulse()
    }
}
