import SwiftUI
import UIKit

/// Public (unauthenticated) artwork image, e.g. a Deezer CDN URL, loaded through `ImageCache`
/// without the bearer token. Re-fetches when `urlString` changes; shows a placeholder until loaded.
struct RemoteArtworkImage: View {
    /// Absolute external image URL (e.g. Deezer CDN). Nil or invalid shows the placeholder.
    let urlString: String?
    /// VoiceOver label. Defaults to "artwork" so VoiceOver doesn't read the raw "Image" trait.
    var accessibilityLabel: String = "artwork"
    /// SF Symbol on the no-artwork tile.
    var placeholderSymbol: String = "music.note.list"
    /// Shrinks the image to at most this many pixels on its longer side; pass about the shown size × 3.
    var maxPixel: Int? = nil

    /// The loaded image and the URL it came from; an image for an earlier URL is never shown.
    @State private var loaded: (url: URL, image: UIImage)?

    private var resolvedURL: URL? {
        guard let s = urlString, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var shown: UIImage? {
        guard let url = resolvedURL else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return ImageCache.shared.cachedImage(for: url, maxPixel: maxPixel)
    }

    var body: some View {
        // A cached image shows on the first frame; a miss shows the placeholder until `.task` loads it.
        ZStack {
            if let img = shown {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .task(id: resolvedURL) {
            if let url = resolvedURL {
                // authenticated: false — this view is for PUBLIC/external artwork (Deezer CDN,
                // share-viewer cover-art). It must never attach the bearer token, matching its
                // documented "unauthenticated" contract.
                loaded = (try? await ImageCache.shared.fetch(url: url, authenticated: false, maxPixel: maxPixel)).map { (url, $0) }
            } else {
                loaded = nil
            }
        }
    }

    // MARK: - Placeholder

    private var placeholder: some View {
        ZStack {
            KimaColor.surface
            Image(systemName: placeholderSymbol)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(KimaColor.textMuted)
        }
    }
}
