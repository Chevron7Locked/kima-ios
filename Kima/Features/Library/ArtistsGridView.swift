import SwiftUI

/// Paginated artists grid for the Collection screen.
/// Adaptive LazyVGrid, square cards with a crafted accent play badge.
struct ArtistsGridView: View {
    let phase: LoadPhase<[Artist]>
    /// Pre-sorted list (name/name-desc sorted client-side by CollectionViewModel).
    let sortedArtists: [Artist]
    /// The search typed above the grid ("" for none).
    let searchText: String
    /// The artists whose play requests are in flight (their badges spin, taps are ignored).
    let playingIds: Set<String>
    let onTapArtist: (String) -> Void
    let onPlayArtist: (String) -> Void
    let onRetry: () -> Void

    var body: some View {
        switch phase {
        case .loading:
            LibraryGridSkeleton(subtitleWidth: 60)
        case .failed(let msg):
            KimaErrorState(message: msg, onRetry: onRetry)
        case .loaded:
            if sortedArtists.isEmpty {
                LibraryEmptyState(icon: "person.2", noun: "artists", query: searchText)
            } else {
                LibraryCardGrid(items: sortedArtists) { artist in
                    LibraryGridCard(
                        coverId: artist.coverArt ?? artist.image,
                        title: artist.effectiveName,
                        subtitle: Self.albumCountLabel(artist),
                        a11yLabel: artistA11yLabel(artist),
                        menuType: .artist,
                        menuId: artist.id,
                        addSource: .artist(id: artist.id),
                        isBusy: playingIds.contains(artist.id),
                        onTap: { onTapArtist(artist.id) },
                        onPlay: { onPlayArtist(artist.id) }
                    )
                }
            }
        }
    }

    /// Visible card subtitle: "N albums", else "N tracks" when the album count is 0 or missing
    /// (the server's stored counter can lag), else nil so the line is hidden.
    static func albumCountLabel(_ artist: Artist) -> String? {
        let albums = artist.albumCount ?? artist.albums?.count ?? 0
        if albums > 0 { return "\(albums) \(albums == 1 ? "album" : "albums")" }
        let tracks = artist.trackCount ?? 0
        if tracks > 0 { return "\(tracks) \(tracks == 1 ? "track" : "tracks")" }
        return nil
    }

    // Combined VoiceOver label — "Artist Name, N albums" (name alone when no count is known).
    private func artistA11yLabel(_ artist: Artist) -> String {
        guard let count = Self.albumCountLabel(artist) else { return artist.effectiveName }
        return "\(artist.effectiveName), \(count)"
    }
}
