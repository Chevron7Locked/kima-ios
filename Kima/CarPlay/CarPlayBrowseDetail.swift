import CarPlay
import Foundation
import UIKit

// MARK: - CarPlayBrowseDetail
//
// Podcasts + Playlists, pushed from the home screen's BROWSE rows; each pushes a second (episode / track) list.
// Each push shows its template immediately (loading state) and fetches in its own Task.

// MARK: - Podcasts

extension CarPlayBrowse {

    static func pushPodcastsList(env: AppEnvironment, interfaceController: CPInterfaceController) {
        let template = pushLoadingCarPlayList(title: "podcasts", on: interfaceController)

        Task { @MainActor in
            do {
                let podcasts = try await env.client.getPodcasts()
                guard !podcasts.isEmpty else {
                    setCarPlayListEmpty(
                        template, title: "no podcasts yet",
                        subtitle: "subscribe to a podcast on your phone to see it here."
                    )
                    return
                }
                // Podcast covers as a shelf grid — the episode list one level down (below) stays
                // as art-thumbnail text rows since episode metadata is text-heavy (title, date,
                // duration) in a way a bare cover grid can't convey.
                let shelves = await CarPlayCoverShelf.buildShelves(
                    maxShelves: 5, allItems: podcasts, env: env, interfaceController: interfaceController
                ) { podcast in
                    CarPlayCoverShelf.Entry(title: podcast.title, coverId: podcast.coverUrl) {
                        Task { @MainActor in
                            pushPodcastEpisodes(podcastId: podcast.id, title: podcast.title, env: env, interfaceController: interfaceController)
                        }
                    }
                }
                setCarPlayListLoaded(template, rows: shelves)
            } catch {
                setCarPlayListLoadFailed(template)
            }
        }
    }

    /// Pushes an episode list for one podcast, fetched fresh via `getPodcast(id:)` — the
    /// subscribed-list response only embeds the latest 5 episodes; the detail endpoint returns
    /// all of them, which is also what `queue` needs for correct auto-advance.
    static func pushPodcastEpisodes(
        podcastId: String, title: String, env: AppEnvironment, interfaceController: CPInterfaceController
    ) {
        let template = pushLoadingCarPlayList(title: title, on: interfaceController)

        Task { @MainActor in
            do {
                let podcast = try await env.client.getPodcast(id: podcastId)
                guard !podcast.episodes.isEmpty else {
                    setCarPlayListEmpty(
                        template, title: "no episodes yet",
                        subtitle: "new episodes will show up here after the next refresh."
                    )
                    return
                }
                let capped = clampedForCarPlay(podcast.episodes)
                var rows = capped.map { episodeRow(for: $0, podcast: podcast, queue: podcast.episodes, env: env, interfaceController: interfaceController) }
                if capped.count < podcast.episodes.count {
                    rows.append(moreNoticeItem(remaining: podcast.episodes.count - capped.count))
                }
                setCarPlayListLoaded(template, rows: rows)
            } catch {
                setCarPlayListLoadFailed(template)
            }
        }
    }

    private static func episodeRow(
        for episode: Episode, podcast: Podcast, queue: [Episode],
        env: AppEnvironment, interfaceController: CPInterfaceController
    ) -> CPListItem {
        let row = CPListItem(text: episode.title, detailText: episodeDetailText(for: episode), image: CarPlayArtwork.placeholder)
        if let pct = episode.progress?.progress { row.playbackProgress = CGFloat(pct / 100) }
        row.handler = { _, completion in
            Task { @MainActor in
                CarPlayPlayback.playPodcastEpisode(episode, podcast: podcast, queue: queue, env: env)
                completion()
            }
        }
        // Episodes without their own artwork fall back to the podcast's cover.
        attachArtwork(to: row, coverId: episode.imageUrl ?? podcast.coverUrl, env: env, interfaceController: interfaceController)
        return row
    }

    private static func episodeDetailText(for episode: Episode) -> String {
        let durationText = carPlayTimeText(seconds: episode.duration)
        guard let date = Formatters.parseISO8601(episode.publishedAt) else { return durationText }
        return "\(durationText) · \(Formatters.displayDate(date))"
    }
}

// MARK: - Playlists

extension CarPlayBrowse {

    static func pushPlaylistsList(env: AppEnvironment, interfaceController: CPInterfaceController) {
        let template = pushLoadingCarPlayList(title: "playlists", on: interfaceController)

        Task { @MainActor in
            do {
                // Mirror `PlaylistsListViewModel.visiblePlaylists` — a playlist hidden on the
                // phone must not leak into CarPlay.
                let playlists = try await env.client.getPlaylists().filter { $0.isHidden != true }
                guard !playlists.isEmpty else {
                    setCarPlayListEmpty(
                        template, title: "no playlists yet",
                        subtitle: "playlists you create or follow will show up here."
                    )
                    return
                }
                // Playlist cover art comes from its first track's album art (playlists have no
                // cover of their own).
                let shelves = await CarPlayCoverShelf.buildShelves(
                    maxShelves: 5, allItems: playlists, env: env, interfaceController: interfaceController
                ) { playlist in
                    CarPlayCoverShelf.Entry(
                        title: playlist.name, coverId: playlist.items?.first?.track.album?.coverUrl
                    ) {
                        Task { @MainActor in
                            pushPlaylistTracks(playlistId: playlist.id, name: playlist.name, env: env, interfaceController: interfaceController)
                        }
                    }
                }
                setCarPlayListLoaded(template, rows: shelves)
            } catch {
                setCarPlayListLoadFailed(template)
            }
        }
    }

    static func pushPlaylistTracks(
        playlistId: String, name: String, env: AppEnvironment, interfaceController: CPInterfaceController
    ) {
        let template = pushLoadingCarPlayList(title: name, on: interfaceController)

        Task { @MainActor in
            do {
                let detail = try await env.client.getPlaylist(id: playlistId)
                let items = detail.items ?? []
                guard !items.isEmpty else {
                    setCarPlayListEmpty(
                        template, title: "no tracks yet",
                        subtitle: "add tracks on your phone to play them here."
                    )
                    return
                }
                let capped = clampedForCarPlay(items)
                var rows = capped.enumerated().map { index, item in
                    playlistTrackRow(for: item, index: index, allItems: items, env: env, interfaceController: interfaceController)
                }
                if capped.count < items.count { rows.append(moreNoticeItem(remaining: items.count - capped.count)) }
                setCarPlayListLoaded(template, rows: rows)
            } catch {
                setCarPlayListLoadFailed(template)
            }
        }
    }

    /// `index`/`allItems` are the FULL (untruncated) playlist so playback + skip/next behave
    /// like the phone app even when the visible CarPlay rows were capped.
    private static func playlistTrackRow(
        for item: PlaylistItem, index: Int, allItems: [PlaylistItem],
        env: AppEnvironment, interfaceController: CPInterfaceController
    ) -> CPListItem {
        let row = CPListItem(text: item.track.title, detailText: item.track.album?.artist?.name, image: CarPlayArtwork.placeholder)
        row.handler = { _, completion in
            Task { @MainActor in
                CarPlayPlayback.playPlaylistTrack(at: index, items: allItems, env: env)
                completion()
            }
        }
        attachArtwork(to: row, coverId: item.track.album?.coverArt, env: env, interfaceController: interfaceController)
        return row
    }
}
