import SwiftUI

// MARK: - SearchResultSections

/// Result sections for the current filter scope: alias banner, top match, songs, albums,
/// podcasts, audiobooks, related artists (web parity).
struct SearchResultSections: View {
    let vm: SearchViewModel
    let onPlayTracks: ([Track], Int) -> Void
    let onPushRoute:  (SearchRoute) -> Void

    var body: some View {
        let lib     = vm.libraryResults
        let filter  = vm.activeFilter
        let showLib = filter == .all || filter == .library
        let showDis = filter == .all || filter == .discover

        // Top match is filter-agnostic (web parity): the best hit across library and discover under
        // every filter. A library artist wins; a discover artist is the fallback.
        let libArtist:  Artist?         = lib?.artists.first
        let discArtist: DiscoverResult? = vm.discoverResults.first(where: { $0.type == .music })
        let hasTopMatch = libArtist != nil || discArtist != nil

        let tracks     = showLib ? (lib?.tracks ?? [])     : []
        let albums     = showLib ? (lib?.albums ?? [])     : []
        let podcasts   = showLib ? (lib?.podcasts ?? [])   : []
        let audiobooks = showLib ? (lib?.audiobooks ?? []) : []
        let episodes   = showLib ? (lib?.episodes ?? [])   : []
        let related    = showDis ? vm.similarArtists       : []

        return VStack(alignment: .leading, spacing: 0) {

            // — Alias correction banner
            if let alias = vm.aliasInfo, showDis {
                AliasInfoBanner(aliasInfo: alias)
            }

            // TOP MATCH
            if hasTopMatch {
                SearchTopResultCard(
                    libraryArtist:  libArtist,
                    discoverArtist: discArtist,
                    onTap: libArtist.map { a in { onPushRoute(.artist(id: a.id)) } }
                        ?? discArtist.map { d in { onPushRoute(.artist(id: d.routeId)) } }
                )
            }

            // SONGS (library)
            if !tracks.isEmpty {
                SearchSongsSection(tracks: tracks, onPlay: onPlayTracks)
            }

            // ALBUMS (library)
            if !albums.isEmpty {
                SearchAlbumsSection(albums: albums) { album in
                    onPushRoute(.album(id: album.id))
                }
            }

            // PODCASTS (library subscriptions)
            if !podcasts.isEmpty {
                SearchPodcastsSection(podcasts: podcasts) { podcast in
                    onPushRoute(.podcast(id: podcast.id))
                }
            }

            // AUDIOBOOKS (library)
            if !audiobooks.isEmpty {
                SearchAudiobooksSection(audiobooks: audiobooks) { book in
                    onPushRoute(.audiobook(id: book.id))
                }
            }

            // PODCAST EPISODES (library)
            if !episodes.isEmpty {
                SearchEpisodesSection(episodes: episodes) { episode in
                    onPushRoute(.podcast(id: episode.podcastId))
                }
            }

            // RELATED ARTISTS (similar artists from /search/discover/similar)
            if !related.isEmpty {
                SearchRelatedArtistsSection(artists: related) { artist in
                    onPushRoute(.artist(id: artist.routeId))
                }
            }

            MiniPlayerClearanceSpacer()
        }
    }
}
