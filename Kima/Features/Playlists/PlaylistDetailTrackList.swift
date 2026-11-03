import SwiftUI

// MARK: - PlaylistDetailTrackList

/// Track listing section of Playlist Detail (split out to keep files under 350 lines): tap to play from that index,
/// swipe-to-remove and drag-to-reorder (owner only), empty state. The owner supplies `onRemove` / `onMove` so this stays pure UI.
struct PlaylistDetailTrackList<Header: View>: View {
    let playlist: PlaylistDetail
    let player: PlaybackController
    let onRemove: (String) -> Void      // trackId
    let onMove: (IndexSet, Int) -> Void
    let onAddToPlaylist: (Track) -> Void   // add this track to ANOTHER playlist
    let buildTracks: ([PlaylistItem]) -> [Track]
    let header: () -> Header

    init(
        playlist: PlaylistDetail,
        player: PlaybackController,
        onRemove: @escaping (String) -> Void,
        onMove: @escaping (IndexSet, Int) -> Void,
        onAddToPlaylist: @escaping (Track) -> Void,
        buildTracks: @escaping ([PlaylistItem]) -> [Track],
        @ViewBuilder header: @escaping () -> Header
    ) {
        self.playlist = playlist
        self.player = player
        self.onRemove = onRemove
        self.onMove = onMove
        self.onAddToPlaylist = onAddToPlaylist
        self.buildTracks = buildTracks
        self.header = header
    }

    @Environment(ToastCenter.self) private var toast

    @State private var editMode: EditMode = .inactive
    private var isOwner: Bool { playlist.isOwner == true }
    private var items: [PlaylistItem] { playlist.items ?? [] }
    private var allTracks: [Track] { buildTracks(items) }

    var body: some View {
        let allTracks = allTracks
        return List {
            // Non-reorderable header block (hero + action bar from parent)
            header()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

            if items.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            } else {
                sectionHeader
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    PlaylistTrackRow(
                        item: item,
                        index: idx,
                        isPlaying: player.currentTrack?.id == item.track.id && player.isPlaying,
                        isCurrent: player.currentTrack?.id == item.track.id,
                        isOwner: isOwner,
                        onPlay: { player.play(tracks: allTracks, startAt: idx) },
                        onNext: { announcePlayNext(player.playNext(allTracks[idx]), in: toast) },
                        onQueue: { announceEnqueue(player.enqueue(track: allTracks[idx]), in: toast) },
                        onAddToPlaylist: { onAddToPlaylist(allTracks[idx]) },
                        onRemove: { onRemove(item.track.id) }
                    )
                    // Hairline between rows, gutter to gutter (the row insets are the gutter).
                    .overlay(alignment: .bottom) {
                        if idx < items.count - 1 { KimaHairline() }
                    }
                    .draggable(TrackTransferable(track: allTracks[idx]))
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: KimaSpacing.lg, bottom: 0, trailing: KimaSpacing.lg))
                    .listRowSeparator(.hidden)
                }
                .onMove(perform: isOwner ? { source, dest in onMove(source, dest) } : nil)
                .onDelete(perform: isOwner ? { idx in
                    idx.forEach { onRemove(items[$0].track.id) }
                } : nil)
            }

            MiniPlayerClearanceSpacer()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        // Let the hero backdrop (first row) reach the true top edge (under the notch). Only .top —
        // the bottom mini-player / tab-bar insets stay intact. The header's backdrop is extended by
        // the measured top inset (see PlaylistDetailView.heroSection) so it fills the exposed strip.
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.editMode, $editMode)
    }

    // MARK: - Section header

    /// Shared setlist header. The count is muted meta, not an accent.
    private var sectionHeader: some View {
        KimaSectionHeader(title: "tracks") {
            HStack(spacing: KimaSpacing.md) {
                Text("\(items.count)")
                    .font(KimaType.caption)
                    .monospacedDigit()
                    .foregroundStyle(KimaColor.textMuted)
                if isOwner {
                    Button {
                        withAnimation { editMode = editMode == .active ? .inactive : .active }
                    } label: {
                        Text(editMode == .active ? "done" : "reorder")
                            .font(KimaType.meta)
                            .foregroundStyle(editMode == .active ? KimaColor.textPrimary : KimaColor.textMuted)
                            .kimaHitTarget(growsLayout: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        KimaEmptyState(icon: "music.note.list", title: "no tracks yet",
                       message: "add tracks from the library to get started")
    }
}

// MARK: - PlaylistTrackRow

private struct PlaylistTrackRow: View {
    let item: PlaylistItem
    let index: Int
    let isPlaying: Bool
    let isCurrent: Bool
    let isOwner: Bool
    let onPlay: () -> Void
    let onNext: () -> Void
    let onQueue: () -> Void
    let onAddToPlaylist: () -> Void
    let onRemove: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// On a phone the album folds into the muted meta line so the title keeps the width.
    private var metaLine: String {
        let artist = item.track.album?.artist?.name ?? ""
        let album = item.track.album?.title ?? ""
        guard hSizeClass == .compact else { return artist }
        return [artist, album].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onPlay) {
            TrackRow(number: "\(index + 1)", artwork: .server(item.track.album?.coverArt), title: item.track.title,
                     subtitle: metaLine, albumColumn: hSizeClass != .compact ? item.track.album?.title : nil,
                     duration: item.track.duration.durationFormatted,
                     nowPlaying: isPlaying ? .playing : (isCurrent ? .current : .none),
                     highlight: env.accent.color)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onPlay() } label: { Label("play", systemImage: "play.fill") }
            Button { onNext() } label: { Label("play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { onQueue() } label: { Label("add to queue", systemImage: "text.badge.plus") }
            Button { onAddToPlaylist() } label: { Label("add to playlist", systemImage: "music.note.list") }
            if isOwner {
                Divider()
                Button(role: .destructive) { onRemove() } label: {
                    Label("remove from playlist", systemImage: "trash")
                }
            }
        }
    }
}
