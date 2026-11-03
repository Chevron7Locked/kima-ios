import SwiftUI

// MARK: - Skeleton

/// Animated placeholder rail shown while the browse query is in flight.
/// Matches web FeaturedPlaylistsSkeleton: 6 pulsing card outlines in a horizontal scroll.
private struct PlaylistRailSkeleton: View {
    private let cardWidth: CGFloat = 148

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KimaSpacing.md) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                        RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                            .fill(KimaColor.surface)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(width: cardWidth)

                        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                            Capsule()
                                .fill(KimaColor.surface)
                                .frame(width: 100, height: 12)
                            Capsule()
                                .fill(KimaColor.surface)
                                .frame(width: 60, height: 10)
                        }
                        .padding(.horizontal, KimaSpacing.xs)
                    }
                    .frame(width: cardWidth)
                }
            }
            .kimaSkeletonPulse()
            .padding(.leading, KimaSpacing.lg)
            .padding(.trailing, KimaSpacing.xl)
        }
    }
}

// MARK: - PlaylistCard

/// Card for a Deezer-sourced featured playlist. `imageUrl` is an absolute, publicly accessible CDN URL, so it
/// uses `RemoteArtworkImage` (ImageCache-backed) with no bearer auth. `onTap` is forwarded to the parent.
private struct PlaylistCard: View {
    let playlist: HomePlaylistPreview
    var onTap: (() -> Void)? = nil
    var width: CGFloat = 148

    var body: some View {
        KimaCoverCard(title: playlist.title,
                      subtitle: "\(playlist.trackCount) \(playlist.trackCount == 1 ? "track" : "tracks")",
                      onTap: { onTap?() }) {
            RemoteArtworkImage(urlString: playlist.imageUrl)
        }
        .frame(width: width)
    }
}

// MARK: - FeaturedPlaylistsSection

/// Home section for Deezer-sourced featured playlists. Always rendered: shows `PlaylistRailSkeleton` while
/// `isBrowseLoading && playlists.isEmpty`, and disappears only when loading is done and the list is empty.
/// See All opens the full playlist grid (`onSeeAll`); a card tap goes to `onPlaylistTap`.
struct FeaturedPlaylistsSection: View {
    let playlists: [HomePlaylistPreview]
    /// True while GET /api/browse/all is in flight (runs independently of the main isLoading gate).
    let isBrowseLoading: Bool
    /// Called when the user taps "See All" — push BrowsePlaylistsView.
    var onSeeAll: (() -> Void)? = nil
    /// Called with the playlist id when a card is tapped — push BrowsePlaylistDetailView.
    var onPlaylistTap: ((String) -> Void)? = nil

    var body: some View {
        // Vanish entirely when load is done and there's nothing to show
        if isBrowseLoading || !playlists.isEmpty {
            VStack(spacing: 0) {
                KimaSectionHeader(
                    title: "featured playlists",
                    badge: "Deezer",
                    onSeeAll: onSeeAll
                )
                if isBrowseLoading && playlists.isEmpty {
                    PlaylistRailSkeleton()
                } else {
                    KimaRail(tileWidth: 148) { width in
                        ForEach(playlists.prefix(20)) { playlist in
                            PlaylistCard(
                                playlist: playlist,
                                onTap: { onPlaylistTap?(playlist.id) },
                                width: width
                            )
                        }
                    }
                }
            }
        }
    }
}
