import SwiftUI

/// Scrollable sections below the hero: popular tracks, discography, available albums, similar
/// artists, bio.
struct ArtistSectionsView: View {
    let artist: Artist
    let vm: ArtistDetailViewModel
    let albums: [Album]
    let onTapAlbum: (String) -> Void
    let onTapArtist: (String) -> Void
    let server: KimaServer

    @Environment(PlaybackController.self) private var player

    private var ownedAlbums: [Album] { vm.ownedAlbums(from: albums) }
    private var availableAlbums: [Album] { vm.availableAlbums(from: albums) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Bio / About
            if let bio = artist.userSummary ?? artist.bio ?? artist.summary, !bio.isEmpty {
                ArtistBioSection(bio: bio)
            }

            // Popular Tracks (top 10)
            if let topTracks = artist.topTracks, !topTracks.isEmpty {
                ArtistPopularTracksSection(
                    tracks: Array(topTracks.prefix(10)),
                    allTracks: topTracks,
                    artistName: artist.name,
                    vm: vm,
                    server: server,
                    currentTrackId: player.currentTrack?.id
                )
            }

            // Discography (owned albums only)
            if !ownedAlbums.isEmpty {
                ArtistDiscographySection(
                    albums: vm.sortedAlbums(ownedAlbums),
                    vm: vm,
                    onTapAlbum: onTapAlbum
                )
            }

            // Available albums to download (unowned). Sorted like the discography: the server's
            // album order is insertion order, so an unsorted section reads as random.
            if !availableAlbums.isEmpty {
                ArtistAvailableAlbumsSection(albums: vm.sortedAlbums(availableAlbums), vm: vm, onTapAlbum: onTapAlbum)
            }

            // Similar Artists
            if let similar = artist.similarArtists, !similar.isEmpty {
                ArtistSimilarArtistsSection(artists: similar, onTapArtist: onTapArtist)
            }
        }
    }
}

// MARK: - Popular Tracks

private struct ArtistPopularTracksSection: View {
    let tracks: [Track]
    let allTracks: [Track]
    let artistName: String
    let vm: ArtistDetailViewModel
    let server: KimaServer
    let currentTrackId: String?

    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: "popular")

            VStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                    let isOwned = !isUnowned(track)
                    let isPlaying = currentTrackId == track.id
                    let isPreviewing = vm.preview.previewingId == track.id

                    PopularTrackRow(
                        track: track,
                        index: idx + 1,
                        isOwned: isOwned,
                        isPlaying: isPlaying,
                        isPreviewing: isPreviewing,
                        onTap: {
                            if isOwned {
                                let start = allTracks.firstIndex(where: { $0.id == track.id }) ?? idx
                                player.play(tracks: allTracks, startAt: start, shuffle: false)
                            } else {
                                togglePreview(track)
                            }
                        }
                    )
                    .contextMenu {
                        // Owned tracks only — unowned/preview rows have no library track id.
                        if isOwned {
                            TrackQueueMenuItems(track: track, player: player, playlistPicker: env.playlistPicker, toast: toast)
                        }
                    }
                    .padding(.horizontal, KimaSpacing.lg)
                    if idx < tracks.count - 1 {
                        KimaHairline()
                            .padding(.horizontal, KimaSpacing.lg)
                    }
                }
            }
        }
    }

    private func togglePreview(_ track: Track) {
        Task {
            await vm.preview.toggle(id: track.id, mainPlayer: player) {
                await vm.previewURL(track: track, artistName: artistName, server: server,
                                    client: env.client)
            }
        }
    }

    /// Web logic: unowned track has no valid album reference.
    private func isUnowned(_ track: Track) -> Bool {
        // NOTE: "Unknown Album" is the server-generated placeholder (title-case) — this is a DATA comparison, not display copy; do not lowercase it.
        track.album?.id == nil || track.album?.title == nil || track.album?.title == "Unknown Album"
    }
}

/// Number · art · title over one quiet line · duration. The line carries what the old extra columns did:
/// "preview" for a track not in the library (a tap plays its 30-second clip) and the play count.
private struct PopularTrackRow: View {
    let track: Track
    let index: Int
    let isOwned: Bool
    let isPlaying: Bool
    let isPreviewing: Bool
    let onTap: () -> Void

    @Environment(AppEnvironment.self) private var env

    private var subtitle: String {
        var parts: [String] = []
        if isOwned {
            if let album = track.album?.title { parts.append(album) }
        } else {
            parts.append(isPreviewing ? "previewing" : "preview")
        }
        if let count = track.playCount, count > 0 { parts.append("\(count.abbreviatedCount) plays") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onTap) {
            TrackRow(number: "\(index)", artwork: .server(track.album?.coverArt), title: track.effectiveTitle,
                     subtitle: subtitle, duration: track.duration.durationFormatted,
                     nowPlaying: isPlaying || isPreviewing ? .playing : .none,
                     highlight: env.accent.color)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("popular-row-\(index)")
        .accessibilityHint(isOwned ? "" : (isPreviewing ? "stops the preview" : "plays a 30-second preview"))
    }
}

// MARK: - Discography (owned)

private struct ArtistDiscographySection: View {
    let albums: [Album]
    let vm: ArtistDetailViewModel
    let onTapAlbum: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: KimaSpacing.md)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Shared setlist/gig-poster header — same primitive every other section (and
            // every other detail screen) uses, with the sort menu as its trailing slot.
            KimaSectionHeader(title: "discography") {
                Menu {
                    ForEach(ArtistDetailViewModel.AlbumSort.allCases) { sort in
                        Button(sort.rawValue) { vm.albumSortOrder = sort }
                    }
                } label: {
                    HStack(spacing: KimaSpacing.xs) {
                        Text(vm.albumSortOrder.rawValue)
                            .font(KimaType.meta)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(KimaColor.textMuted)
                    .kimaHitTarget(growsLayout: false)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, spacing: KimaSpacing.xl) {
                ForEach(albums) { album in
                    let year = (album.displayYear ?? album.year).map(String.init)
                    KimaCoverCard(title: album.effectiveTitle, subtitle: year, titleLines: 2,
                                  onTap: { onTapAlbum(album.id) }) {
                        CoverArtImage(coverId: album.userCoverUrl ?? album.coverArt ?? album.coverUrl,
                                      size: 256, cornerRadius: 0)
                    }
                }
            }
            .padding(.horizontal, KimaSpacing.lg)
        }
    }
}

