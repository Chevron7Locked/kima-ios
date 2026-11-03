import SwiftUI

// MARK: - PopularArtistCard

/// Card for a Last.FM popular artist: square cover, listener count subtitle. Tappable only when `onTap` is
/// provided (the artist matched a library entry); otherwise inert. `image` is a relative cover-art identifier
/// resolved by CoverArtImage to an authenticated server URL.
private struct PopularArtistCard: View {
    let artist: HomePopularArtist
    var onTap: (() -> Void)? = nil
    var width: CGFloat = 148

    var body: some View {
        KimaCoverCard(title: artist.name,
                      subtitle: artist.listeners.map { "\($0.formatted()) listeners" },
                      onTap: { onTap?() }) {
            CoverArtImage(coverId: artist.image, size: 256, cornerRadius: 0)
        }
        .frame(width: width)
        .disabled(onTap == nil)
    }
}

// MARK: - PopularArtistsSection

/// Home section for Last.FM popular artists, with a "LAST.FM" badge and no See All. A card whose artist matches
/// a library entry (`id != nil`) navigates via `onArtistTap`; unmatched artists are inert.
struct PopularArtistsSection: View {
    let artists: [HomePopularArtist]
    /// Called with the library artist id when a matched artist card is tapped.
    var onArtistTap: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            KimaSectionHeader(title: "popular artists", badge: "Last.fm")
            KimaRail(tileWidth: 148) { width in
                ForEach(artists, id: \.stableId) { artist in
                    PopularArtistCard(
                        artist: artist,
                        onTap: artist.id.map { id in { onArtistTap?(id) } },
                        width: width
                    )
                }
            }
        }
    }
}
