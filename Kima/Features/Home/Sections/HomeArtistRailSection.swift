import SwiftUI

// MARK: - HomeArtistRailSection

/// Home section showing a rail of artist cards under a section header ("recently added",
/// "recommended"). `badge` marks a data source; `onSeeAll` adds a see-all link.
struct HomeArtistRailSection: View {
    let title: String
    var badge: String? = nil
    var onSeeAll: (() -> Void)? = nil
    let artists: [Artist]
    /// Called with the artist id when a card is tapped; caller routes to ArtistDetailView.
    let onArtistTap: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            KimaSectionHeader(title: title, badge: badge, onSeeAll: onSeeAll)
            KimaRail(tileWidth: 148) { width in
                ForEach(artists) { artist in
                    KimaCoverCard(title: artist.effectiveName, titleLines: 2, onTap: { onArtistTap(artist.id) }) {
                        CoverArtImage(coverId: artist.coverArt ?? artist.image, size: 256, cornerRadius: 0)
                    }
                    .frame(width: width)
                }
            }
        }
    }
}
