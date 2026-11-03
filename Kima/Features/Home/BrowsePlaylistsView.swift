import SwiftUI

// MARK: - BrowsePlaylistsView

/// "See All" destination for the Featured Playlists rail. Uses the playlists HomeView already
/// loaded; card taps push into HomeView's NavigationStack through the `$path` it passes in.
@MainActor
struct BrowsePlaylistsView: View {
    let playlists: [HomePlaylistPreview]
    /// Parent NavigationStack path — append `.browsePlaylistDetail(id:)` to push a detail view.
    @Binding var path: [LibraryRoute]

    // Adaptive columns: iPhone yields ~2 per row; iPad shows more as width allows.
    // Top-aligned so a card with a one-line title starts level with a two-line neighbour.
    private let columns = [GridItem(.adaptive(minimum: 155), spacing: KimaSpacing.md, alignment: .top)]

    var body: some View {
        ZStack {
            KimaScreenGround()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    headerSection
                    if playlists.isEmpty {
                        emptyState
                    } else {
                        playlistGrid
                    }
                }
            }
            .kimaScrollTopGround()
            .kimaMiniPlayerClearance()
            .scrollBounceBehavior(.basedOnSize)
        }
        // System back button in a transparent bar, like the other pushed screens.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }

    // MARK: - Header

    private var headerSection: some View {
        KimaScreenHeader(title: "featured playlists", statValue: playlists.count,
                         statLabel: playlists.count == 1 ? "playlist from Deezer" : "playlists from Deezer")
            .padding(.bottom, KimaSpacing.md)
    }

    // MARK: - Grid

    private var playlistGrid: some View {
        LazyVGrid(columns: columns, spacing: KimaSpacing.xl) {
            ForEach(playlists) { playlist in
                BrowsePlaylistGridCard(playlist: playlist) {
                    path.append(.browsePlaylistDetail(id: playlist.id))
                }
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: KimaSpacing.md) {
            Image(systemName: "music.note.list")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(KimaColor.textMuted)
            Text("no featured playlists available")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, KimaSpacing.huge)
    }
}

// MARK: - BrowsePlaylistGridCard

/// 2-column grid card for a Deezer browse playlist.
/// Artwork fills top square; title + track count below.
private struct BrowsePlaylistGridCard: View {
    let playlist: HomePlaylistPreview
    let onTap: () -> Void

    var body: some View {
        KimaCoverCard(title: playlist.title, subtitle: subtitle, titleLines: 2, onTap: onTap) {
            RemoteArtworkImage(urlString: playlist.imageUrl)
        }
    }

    /// "creator · N tracks", or the count alone.
    private var subtitle: String {
        let count = "\(playlist.trackCount) \(playlist.trackCount == 1 ? "track" : "tracks")"
        guard let creator = playlist.creator, !creator.isEmpty else { return count }
        return "\(creator) · \(count)"
    }
}
