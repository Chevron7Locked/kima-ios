import SwiftUI

// MARK: - PodcastHeroView
//
// Hero shared by subscribed (Podcast) and preview (PodcastPreview) modes; it takes raw display data so neither needs
// its own hero struct. The page pins PodcastHeroBackdrop behind it, with the CoverArtColor palette it loads.

struct PodcastHeroView: View {
    let coverUrl: String?
    let title: String
    let author: String
    let genres: [String]?
    let episodeCount: Int?
    /// Top safe-area inset — pads the hero content below the status bar; the page's backdrop fills behind this pad.
    var topSafeInset: CGFloat = 0

    var body: some View {
        KimaDetailHero(topInset: topSafeInset) {
            CoverArtImage(coverId: coverUrl, size: 512, cornerRadius: KimaRadius.hero, placeholderSymbol: "mic")
        } info: {
            KimaKicker(title: "podcast")
            KimaDetailHeroTitle(text: title)
            KimaDetailHeroByline(text: author)
            metaLine
        }
    }

    /// Up to two genres, then the episode count.
    private var metaLine: some View {
        var parts: [String] = []
        if let genres, !genres.isEmpty { parts.append(genres.prefix(2).joined(separator: ", ").lowercased()) }
        if let episodeCount { parts.append("\(episodeCount) episode\(episodeCount == 1 ? "" : "s")") }
        return KimaDetailHeroMeta(parts: parts)
    }
}

// MARK: - Backdrop

/// The podcast page's colour: the cover blurred and darkened with the palette gradient over it. The page sets it
/// behind the top of the hero and it scrolls away with it (`kimaHeroGround`).
struct PodcastHeroBackdrop: View {
    let coverUrl: String?
    let palette: CoverArtPalette?

    var body: some View {
        KimaCoverColourBackdrop(coverId: coverUrl, palette: palette, topOpacity: 0.28, midOpacity: 0.55)
    }
}
