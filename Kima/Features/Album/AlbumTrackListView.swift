import SwiftUI

// Disc-grouped track list with owned + missing tracks interleaved, play counts, preview tap.

// MARK: - Track list

struct AlbumTrackListView: View {
    let album: Album
    let isOwned: Bool
    let vm: AlbumDetailViewModel
    /// Optional callback invoked when the user chooses "Edit Metadata" from a track's context menu.
    /// Nil → context menu item is omitted. Only passed for owned-album tracks.
    var onEditTrack: ((Track) -> Void)? = nil

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast

    // Read from ViewModel caches rather than recomputing on every body render.
    // The caches are rebuilt in `AlbumDetailViewModel.phase.didSet` — once per load, not per frame.
    private var sections: [AlbumDetailViewModel.DiscSection] { vm.cachedSections }
    // Flat owned queue — used to determine startIndex when tapping a track.
    private var ownedQueue: [Track] { vm.cachedOwnedQueue }

    var body: some View {
        let multiDisc = sections.count > 1
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { section in
                if multiDisc {
                    AlbumDiscHeader(discNumber: section.id, subtitle: section.subtitle)
                }
                ForEach(Array(section.tracks.enumerated()), id: \.element.id) { idx, track in
                    trackRow(track: track, indexInSection: idx)
                        .padding(.horizontal, KimaSpacing.lg)
                    // Hairline between rows, inset to the gutter; none after the last row.
                    if idx < section.tracks.count - 1 {
                        KimaHairline()
                            .padding(.horizontal, KimaSpacing.lg)
                    }
                }
            }
        }
    }

    // MARK: - Row builder

    @ViewBuilder
    private func trackRow(track: Track, indexInSection: Int) -> some View {
        let isMissing = track.isMissing ?? false
        // Preview applies to: missing tracks, OR all tracks when album is unowned
        let needsPreview = isMissing || !isOwned
        let displayNo = track.displayTrackNo ?? track.trackNumber ?? track.trackNo ?? (indexInSection + 1)
        let isActive = !isMissing && player.currentTrack?.id == track.id
        let isPreviewing = vm.preview.previewingId == track.id

        AlbumTrackRow(
            track: track,
            trackNumber: displayNo,
            isMissing: isMissing,
            needsPreview: needsPreview,
            isActive: isActive,
            isActivePlaying: isActive && player.isPlaying,
            isPreviewing: isPreviewing
        ) {
            if needsPreview {
                Task {
                    await vm.preview.toggle(id: track.id, mainPlayer: player) {
                        let tok = await env.client.streamTicket()
                        return previewURL(for: track, token: tok)
                    }
                }
            } else {
                let start = ownedQueue.firstIndex(where: { $0.id == track.id }) ?? 0
                if !ownedQueue.isEmpty {
                    player.play(tracks: ownedQueue, startAt: start, shuffle: false)
                }
            }
        }
        .contextMenu {
            // Owned, real (non-missing) tracks only — discovery/missing rows have no library
            // track id and cannot be queued or added to a playlist.
            if !isMissing, isOwned {
                TrackQueueMenuItems(track: track, player: player, playlistPicker: env.playlistPicker, toast: toast)
            }
            if !isMissing, let onEditTrack {
                Button {
                    onEditTrack(track)
                } label: {
                    Label("edit metadata", systemImage: "pencil")
                }
            }
        }
    }

    private func previewURL(for track: Track, token: String?) -> URL? {
        PreviewURL.track(
            base: env.server,
            artistName: album.artist?.name ?? "",
            trackTitle: track.effectiveTitle,
            token: token
        )
    }
}

// MARK: - Disc header

private struct AlbumDiscHeader: View {
    let discNumber: Int
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            Text(subtitle.map { "disc \(discNumber): \($0)" } ?? "disc \(discNumber)")
                .font(KimaType.meta)
                .foregroundStyle(KimaColor.textMuted)
                .tracking(0.1)
                .padding(.top, KimaSpacing.lg)
                .padding(.bottom, KimaSpacing.xs)
            KimaHairline()
        }
        .padding(.horizontal, KimaSpacing.lg)
    }
}

// MARK: - Track row

private struct AlbumTrackRow: View {
    let track: Track
    let trackNumber: Int
    let isMissing: Bool
    let needsPreview: Bool
    let isActive: Bool
    let isActivePlaying: Bool
    let isPreviewing: Bool

    @Environment(AppEnvironment.self) private var env
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            TrackRow(number: "\(trackNumber)", title: track.effectiveTitle,
                     subtitle: isMissing ? nil : track.artist?.name,
                     duration: (!isMissing || track.duration > 0) ? track.duration.durationFormatted : nil,
                     nowPlaying: isActivePlaying ? .playing : (isActive ? .current : .none),
                     highlight: env.accent.color, isMissing: isMissing) {
                if let count = track.playCount ?? track.userPlayCount, count > 0, !isMissing {
                    KimaTag(text: "\(count)")
                }
                if needsPreview { previewBadge }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isMissing ? "album-track-missing" : "album-track")
        .modifier(TrackDragModifier(track: track, enabled: !needsPreview))
    }

    private var previewBadge: some View {
        PreviewBadge(isActive: isPreviewing, activeColor: env.accent.color)
    }
}
