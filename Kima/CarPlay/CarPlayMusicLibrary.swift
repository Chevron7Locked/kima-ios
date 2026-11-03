import CarPlay
import UIKit

// MARK: - CarPlayMusicLibrary
//
// Artists + Albums browse. Artists lead to artist detail (album shelves, or a flat track list when the artist has
// only topTracks) then album tracks; Albums lead to album tracks. Detail pushes run their own `Task`.

extension CarPlayBrowse {

    // MARK: - Artists

    static func pushArtistsList(env: AppEnvironment, interfaceController: CPInterfaceController) {
        let template = pushLoadingCarPlayList(title: "artists", on: interfaceController)

        Task { @MainActor in
            do {
                let (artists, total) = try await CarPlayBrowse.ownedArtistsInPhoneOrder(env: env)
                guard !artists.isEmpty else {
                    setCarPlayListEmpty(
                        template, title: "no artists yet",
                        subtitle: "artists in your library will show up here."
                    )
                    return
                }
                // Cover shelves for the first artists, then plain rows for the rest, as far as
                // the head unit's list limit allows; "+N more" counts every artist not shown.
                let shelfCount = 5
                let onShelves = Array(artists.prefix(shelfCount * max(1, Int(CPMaximumNumberOfGridImages))))
                var rows = await CarPlayCoverShelf.buildShelves(
                    maxShelves: shelfCount, allItems: onShelves, env: env, interfaceController: interfaceController
                ) { artist in
                    CarPlayCoverShelf.Entry(title: artist.effectiveName, coverId: artist.coverArt ?? artist.image) {
                        CarPlayBrowse.pushArtistDetail(
                            artistId: artist.id, title: artist.effectiveName,
                            env: env, interfaceController: interfaceController
                        )
                    }
                }
                let rest = artists.dropFirst(onShelves.count)
                let room = max(0, Int(CPListTemplate.maximumItemCount) - rows.count - 1)
                rows += rest.prefix(room).map { CarPlayBrowse.artistRow($0, env: env, interfaceController: interfaceController) }
                let notShown = total - onShelves.count - min(room, rest.count)
                if notShown > 0 { rows.append(moreNoticeItem(remaining: notShown)) }
                setCarPlayListLoaded(template, rows: rows)
            } catch {
                setCarPlayListLoadFailed(template)
            }
        }
    }

    /// Every owned artist, in the phone Library's order, and the server's total. Pages of 500.
    private static func ownedArtistsInPhoneOrder(env: AppEnvironment) async throws -> ([Artist], Int) {
        var artists: [Artist] = []
        var total = 0
        repeat {
            let page = try await env.client.getLibraryArtists(
                filter: LibraryFilter.owned.rawValue, sortBy: LibrarySortOption.name.rawValue,
                limit: 500, offset: artists.count)
            total = page.total ?? artists.count + page.artists.count
            if page.artists.isEmpty { break }
            artists += page.artists
        } while artists.count < total
        return (CollectionViewModel.sortedByName(artists), max(total, artists.count))
    }

    private static func artistRow(
        _ artist: Artist, env: AppEnvironment, interfaceController: CPInterfaceController
    ) -> CPListItem {
        let row = CPListItem(text: artist.effectiveName, detailText: nil)
        row.accessoryType = .disclosureIndicator
        row.handler = { _, completion in
            CarPlayBrowse.pushArtistDetail(
                artistId: artist.id, title: artist.effectiveName,
                env: env, interfaceController: interfaceController
            )
            completion()
        }
        return row
    }

    /// Pushed on tap from an Artists shelf. Prefers the artist's albums (rendered as further
    /// cover shelves, one more push away from a playable track list). Falls back to the artist's
    /// `topTracks` — rendered as a directly-playable flat row list — only when there are no
    /// albums at all, so a discovery-origin or single-track artist isn't a dead end.
    static func pushArtistDetail(
        artistId: String, title: String, env: AppEnvironment, interfaceController: CPInterfaceController
    ) {
        let template = pushLoadingCarPlayList(title: title, on: interfaceController)

        Task { @MainActor in
            do {
                let artist = try await env.client.getArtist(id: artistId)
                let albums = artist.albums ?? []
                if !albums.isEmpty {
                    let shelves = await albumShelves(albums, env: env, interfaceController: interfaceController)
                    setCarPlayListLoaded(template, rows: shelves)
                    return
                }

                let topTracks = artist.topTracks ?? []
                guard !topTracks.isEmpty else {
                    setCarPlayListEmpty(
                        template, title: "no albums yet",
                        subtitle: "no albums by \(title) on your server yet."
                    )
                    return
                }
                let capped = clampedForCarPlay(topTracks)
                var rows = capped.enumerated().map { index, track in
                    musicTrackRow(
                        for: track, index: index, allTracks: topTracks, coverId: track.album?.coverArt,
                        env: env, interfaceController: interfaceController
                    )
                }
                if capped.count < topTracks.count {
                    rows.append(moreNoticeItem(remaining: topTracks.count - capped.count))
                }
                setCarPlayListLoaded(template, rows: rows)
            } catch {
                setCarPlayListLoadFailed(template)
            }
        }
    }

    // MARK: - Albums

    /// Album cover shelves; tapping a cover opens that album's track list.
    private static func albumShelves(
        _ albums: [Album], env: AppEnvironment, interfaceController: CPInterfaceController
    ) async -> [CPListTemplateItem] {
        await CarPlayCoverShelf.buildShelves(
            maxShelves: 5, allItems: albums, env: env, interfaceController: interfaceController
        ) { album in
            CarPlayCoverShelf.Entry(title: album.effectiveTitle, coverId: album.coverArt ?? album.coverUrl) {
                CarPlayBrowse.pushAlbumTracks(
                    albumId: album.id, title: album.effectiveTitle,
                    env: env, interfaceController: interfaceController
                )
            }
        }
    }

    static func pushAlbumsList(env: AppEnvironment, interfaceController: CPInterfaceController) {
        let template = pushLoadingCarPlayList(title: "albums", on: interfaceController)

        Task { @MainActor in
            do {
                let response = try await env.client.getLibraryAlbums(limit: 60)
                let albums = response.albums
                guard !albums.isEmpty else {
                    setCarPlayListEmpty(
                        template, title: "no albums yet",
                        subtitle: "albums in your library will show up here."
                    )
                    return
                }
                let shelves = await albumShelves(albums, env: env, interfaceController: interfaceController)
                setCarPlayListLoaded(template, rows: shelves)
            } catch {
                setCarPlayListLoadFailed(template)
            }
        }
    }

    /// Terminal screen for Artists→Albums and the Albums row: a playable track list plus a leading "Play All". Every row's
    /// handler captures `tracks` (the full, untruncated album) as the queue even when visible rows are capped for
    /// CarPlay's list-item limit, like `playlistTrackRow` in CarPlayBrowseDetail.swift.
    static func pushAlbumTracks(
        albumId: String, title: String, env: AppEnvironment, interfaceController: CPInterfaceController
    ) {
        let template = pushLoadingCarPlayList(title: title, on: interfaceController)

        Task { @MainActor in
            do {
                let album = try await env.client.getAlbum(id: albumId)
                let tracks = album.tracksInOrder
                guard !tracks.isEmpty else {
                    setCarPlayListEmpty(
                        template, title: "no tracks yet",
                        subtitle: "this album's tracks aren't available yet."
                    )
                    return
                }
                let coverId = album.coverArt ?? album.coverUrl
                let capped = clampedForCarPlay(tracks)

                let playAll = CPListItem(
                    text: "play all", detailText: "\(tracks.count) track\(tracks.count == 1 ? "" : "s")",
                    image: UIImage(systemName: "play.fill")
                )
                playAll.handler = { _, completion in
                    Task { @MainActor in
                        env.player.play(tracks: tracks, startAt: 0)
                        pushNowPlaying(on: interfaceController)
                        completion()
                    }
                }

                var rows: [CPListItem] = [playAll]
                rows.append(contentsOf: capped.enumerated().map { index, track in
                    musicTrackRow(
                        for: track, index: index, allTracks: tracks, coverId: coverId,
                        env: env, interfaceController: interfaceController
                    )
                })
                if capped.count < tracks.count {
                    rows.append(moreNoticeItem(remaining: tracks.count - capped.count))
                }
                setCarPlayListLoaded(template, rows: rows)
            } catch {
                setCarPlayListLoadFailed(template)
            }
        }
    }

    // MARK: - Track row

    /// `index`/`allTracks` are the full (untruncated) queue for the album or artist top-tracks list, so skip/next line up
    /// even when visible rows were capped. `coverId` is passed in because an album's tracks share one cover; the artist
    /// top-tracks fallback passes each track's own `track.album?.coverArt`, as they can span albums.
    /// `PlaybackController.play(tracks:startAt:)` is synchronous. Pushes Now Playing after starting playback.
    private static func musicTrackRow(
        for track: Track, index: Int, allTracks: [Track], coverId: String?,
        env: AppEnvironment, interfaceController: CPInterfaceController
    ) -> CPListItem {
        let detail: String
        if let artistName = track.artist?.name, !artistName.isEmpty {
            detail = "\(artistName) · \(track.duration.durationFormatted)"
        } else {
            detail = track.duration.durationFormatted
        }
        let row = CPListItem(text: track.effectiveTitle, detailText: detail, image: CarPlayArtwork.placeholder)
        row.handler = { _, completion in
            Task { @MainActor in
                env.player.play(tracks: allTracks, startAt: index)
                pushNowPlaying(on: interfaceController)
                completion()
            }
        }
        attachArtwork(to: row, coverId: coverId, env: env, interfaceController: interfaceController)
        return row
    }
}
