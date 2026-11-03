import SwiftUI

/// Paginated albums grid for the Collection screen.
/// Square cover cards with a play badge, in the library cover grid.
struct AlbumsGridView: View {
    let phase: LoadPhase<[Album]>
    /// The search typed above the grid ("" for none).
    let searchText: String
    /// The albums whose play requests are in flight (their badges spin, taps are ignored).
    let busyIds: Set<String>
    let onTapAlbum: (String) -> Void
    let onPlayAlbum: (String) -> Void
    let onRetry: () -> Void

    var body: some View {
        switch phase {
        case .loading:
            LibraryGridSkeleton(subtitleWidth: 80)
        case .failed(let msg):
            KimaErrorState(message: msg, onRetry: onRetry)
        case .loaded(let albums):
            if albums.isEmpty {
                LibraryEmptyState(icon: "opticaldisc", noun: "albums", query: searchText, pageOnly: true)
            } else {
                LibraryCardGrid(items: albums) { album in
                    LibraryGridCard(
                        coverId: album.coverArt ?? album.coverUrl,
                        title: album.effectiveTitle,
                        subtitle: album.artist?.name,
                        a11yLabel: albumA11yLabel(album),
                        menuType: .album,
                        menuId: album.id,
                        addSource: .album(id: album.id),
                        isBusy: busyIds.contains(album.id),
                        onTap: { onTapAlbum(album.id) },
                        onPlay: { onPlayAlbum(album.id) }
                    )
                }
            }
        }
    }

    // VoiceOver label: "Album Title, Artist Name"
    private func albumA11yLabel(_ album: Album) -> String {
        let title = album.effectiveTitle
        guard let artist = album.artist?.name else { return title }
        return "\(title), \(artist)"
    }
}
