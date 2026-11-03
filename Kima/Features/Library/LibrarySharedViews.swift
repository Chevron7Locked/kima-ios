import SwiftUI

// Library grid pieces shared by the albums, artists and tracks lists: grid columns, empty state,
// grid card and skeleton.

// MARK: - Grid layout

/// Adaptive-grid column spec shared by AlbumsGridView, ArtistsGridView, and their skeleton
/// placeholders.  One definition here keeps all four grid instances in sync.
/// minimum: 155 → iPhone stays ~2 columns; iPad shows more columns naturally.
enum LibraryGrid {
    static let minimumWidth: CGFloat = 155
    static let columns = [GridItem(.adaptive(minimum: minimumWidth), spacing: KimaSpacing.md)]
}

// MARK: - Empty state

/// A library tab with nothing to show. With a search typed it says nothing matched that search,
/// never that the library is empty. `pageOnly`: the search looked through the loaded page only.
struct LibraryEmptyState: View {
    let icon: String
    /// Plural noun for the tab: "artists", "albums", "songs".
    let noun: String
    let query: String
    var pageOnly = false

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            KimaEmptyState(icon: icon, title: "no \(noun) yet", message: "add music on your server to see it here.")
        } else {
            KimaEmptyState(
                icon: "magnifyingglass",
                title: "nothing matches \u{201C}\(q)\u{201D}",
                message: pageOnly ? "only this page of \(noun) is searched" : "searched all your \(noun)"
            )
        }
    }
}

// MARK: - Grid card

/// Which kind of library item a grid card shows.
enum LibraryItemType {
    case artist
    case album
}

/// Album/artist grid card: the shared `KimaCoverCard` with its play badge and mood dot, plus the long-press
/// menu (queue / add to playlist via `libraryItemMenu`) and a combined VoiceOver label.
struct LibraryGridCard: View {
    let coverId: String?
    let title: String
    let subtitle: String?
    let a11yLabel: String
    let menuType: LibraryItemType
    let menuId: String
    let addSource: PlaylistAddSource
    /// The play request for this card is in flight (its badge spins).
    var isBusy: Bool = false
    let onTap: () -> Void
    let onPlay: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast
    @Environment(PlaybackController.self) private var player

    /// Whether the playing track belongs to this album or artist.
    private var isPlayingThis: Bool {
        guard player.isPlaying, let track = player.currentTrack else { return false }
        switch menuType {
        case .album:  return track.album?.id == menuId
        case .artist: return track.artist?.id == menuId
        }
    }

    /// The album's or artist's main mood colour from the vibe map, if it has one.
    private var mood: Color? {
        let moods = env.vibeMapViewModel.libraryMoods
        let key = menuType == .album ? moods.albumMood[menuId] : moods.artistMood[menuId]
        return key.map(VibeMoodPalette.mapColor(for:))
    }

    var body: some View {
        KimaCoverCard(title: title, subtitle: subtitle, mood: mood, isPlaying: isPlayingThis,
                      isBusy: isBusy, onPlay: onPlay, onTap: onTap) {
            CoverArtImage(coverId: coverId, size: 256, cornerRadius: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
        .libraryItemMenu(
            onPlay: onPlay,
            onPlayNext: {
                Task {
                    guard let resolved = await resolvedTracks() else { return }
                    announcePlayNext(env.player.playNext(contentsOf: resolved.tracks),
                                     failedAlbums: resolved.failedAlbums, in: toast)
                }
            },
            onQueue: {
                Task {
                    guard let resolved = await resolvedTracks() else { return }
                    announceEnqueue(env.player.enqueue(tracks: resolved.tracks), name: title,
                                    failedAlbums: resolved.failedAlbums, in: toast)
                }
            },
            onAddToPlaylist: { env.playlistPicker.present(addSource) }
        )
    }

    /// The source's tracks for play next / add to queue; says so when nothing could be loaded.
    private func resolvedTracks() async -> ResolvedTracks? {
        guard let resolved = await env.client.resolveTracks(for: addSource) else {
            toast.show("couldn't load \(title.lowercased())", style: .error)
            return nil
        }
        guard !resolved.tracks.isEmpty else {
            if resolved.failedAlbums > 0 { toast.show(couldntLoadAlbumsText(resolved.failedAlbums), style: .error) }
            return nil
        }
        return resolved
    }
}

// MARK: - Grid skeleton

/// Shared pulsing-placeholder grid for `AlbumsGridView`/`ArtistsGridView` while loading.
/// `subtitleWidth` matches each grid's real subtitle's rough width (album: artist name, wider;
/// artist: track count, narrower).
struct LibraryGridSkeleton: View {
    let subtitleWidth: CGFloat

    var body: some View {
        LazyVGrid(columns: LibraryGrid.columns, spacing: KimaSpacing.xl) {
            ForEach(0..<12, id: \.self) { _ in
                VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                    RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                        .fill(KimaColor.surface)
                        .aspectRatio(1, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(KimaColor.surface)
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(KimaColor.surface)
                        .frame(width: subtitleWidth, height: 10)
                }
            }
        }
        .kimaSkeletonPulse()
    }
}
