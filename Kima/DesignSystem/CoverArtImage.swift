import SwiftUI
import UIKit

/// Authenticated cover-art image with a placeholder fallback (no coverId, bad URL, or failed
/// fetch). Loads through `ImageCache.shared`, which adds the auth header for our server host;
/// `.task(id: coverURL)` restarts the fetch whenever the URL changes.
struct CoverArtImage: View {
    /// The cover identifier from an API response (`coverArt`, `coverUrl`, `image`, etc.).
    let coverId: String?
    /// A pre-resolved image URL that BYPASSES the `coverId` → `CoverArtURL` path. Used for
    /// long-form content (audiobook/podcast) whose artwork is an already-resolved URL
    /// (`LongFormNowPlayingMeta.coverURL`), not a library cover id. When non-nil it wins;
    /// when nil (the default — every music call site) behaviour is unchanged.
    var directURL: URL? = nil
    /// Requested pixel dimension sent to the server (e.g. 48, 256, 512). The view's display
    /// size is set by the parent layout; this controls server-side resize quality.
    let size: Int
    /// Corner radius applied to both the loaded image and the placeholder.
    var cornerRadius: CGFloat = 8
    /// When true the view fills the space its PARENT offers (full-bleed blurred hero backdrops)
    /// instead of locking to a width-driven square, which would leave the cover's right edge
    /// as a hard vertical seam through the blur.
    var fillsContainer: Bool = false
    /// VoiceOver label for the artwork; callers that know the title/artist should pass it.
    var accessibilityLabel: String = "album artwork"
    /// When true, the no-cover fallback is a large cosmic "Kima" tile (accent gradient + a
    /// faint static mark) instead of the flat music-note tile. Reserved for hero contexts
    /// (e.g. the full player) where the placeholder is big and prominent; list/grid rows
    /// keep the minimal tile so small thumbnails don't compete visually.
    var heroPlaceholder: Bool = false
    /// SF Symbol on the no-cover tile: "mic" for podcasts, "book" for audiobooks.
    var placeholderSymbol: String = "music.note"
    /// Called when the cover could not be fetched, so a mosaic can drop it and refit.
    var onFailure: (() -> Void)? = nil

    @Environment(AppEnvironment.self) private var env
    @State private var loaded: UIImage?

    var body: some View {
        // Guaranteed-square (width-driven) container: the image fills it and overflow is clipped. Without it a non-square
        // source (e.g. a landscape artist photo) makes its card taller than its rail-mates and drops its label.
        // Renders an already-cached image synchronously on the first frame (`loaded`, else a non-isolated cache peek) so
        // freshly-mounted art doesn't pop in late during an entrance animation. Misses fall through to placeholder + .task.
        let shown = loaded ?? coverURL.flatMap { ImageCache.shared.cachedImage(for: $0) }
        return ZStack {
            if fillsContainer {
                // Hero-backdrop mode: no aspect lock — the parent's frame (height-driven,
                // full-width) sizes us; the artwork fills via scaledToFill inside.
                Color.clear
            } else {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
            }
        }
            .overlay {
                if let img = shown {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipShape(clip)
            .contentShape(clip)
            .accessibilityLabel(accessibilityLabel)
            .task(id: coverURL) {
                if let url = coverURL {
                    loaded = try? await ImageCache.shared.fetch(url: url)
                    if loaded == nil, !Task.isCancelled { onFailure?() }
                } else {
                    loaded = nil
                }
            }
    }

    // MARK: - Private helpers

    private var coverURL: URL? {
        // Long-form artwork arrives as an already-resolved URL; use it directly.
        if let directURL { return directURL }
        guard let id = coverId, !id.isEmpty else { return nil }
        return CoverArtURL.url(base: env.server, coverId: id, size: size)
    }

    private var clip: AnyShape {
        AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var placeholder: some View {
        if heroPlaceholder {
            heroCosmicPlaceholder
        } else {
            ZStack {
                KimaColor.surface
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(KimaColor.textMuted)
            }
            .clipShape(clip)
        }
    }

    /// Hero "no art yet" tile — reads as Kima, not an empty box. A gradient from the violet
    /// ambient (the web's resting cosmos colour), with a large,
    /// very-low-opacity static mark centered. `living: false` on `KimaMark` keeps this a zero-cost
    /// static fill (no per-frame TimelineView tick).
    private var heroCosmicPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [KimaColor.ambient.opacity(0.35), KimaColor.surfaceRaised, KimaColor.base],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            KimaMark(style: .shiny, living: false)
                .opacity(0.16)
                .scaleEffect(0.6)
        }
        .clipShape(clip)
    }
}
