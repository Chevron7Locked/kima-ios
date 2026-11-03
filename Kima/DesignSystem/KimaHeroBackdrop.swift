import SwiftUI

/// Reads the top inset (status bar + navigation bar) before the scrolling content inside ignores it,
/// so a hero backdrop can reach the top edge while the hero's text clears the bars.
struct KimaTopInsetReader<Content: View>: View {
    @ViewBuilder let content: (_ topInset: CGFloat) -> Content

    var body: some View {
        GeometryReader { proxy in content(proxy.safeAreaInsets.top) }
    }
}

/// A hero's cover art, heavily blurred and darkened, filling a page's hero backdrop (album, podcast); the page
/// colour until the art has loaded. The caller loads the image.
struct KimaBlurredCoverBackdrop: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                KimaPreblurredImage(image: image, radius: 44)
                    .overlay(Color.black.opacity(0.52))
            } else {
                KimaColor.base
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

/// A cover-coloured hero backdrop (album, podcast): the cover blurred and darkened, the palette gradient over it
/// at the page's opacities, and optionally the scrim for pale covers. Loads the art itself; the caller owns `palette`.
struct KimaCoverColourBackdrop: View {
    let coverId: String?
    let palette: CoverArtPalette?
    let topOpacity: Double
    let midOpacity: Double
    var scrim = false

    @Environment(AppEnvironment.self) private var env
    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            KimaBlurredCoverBackdrop(image: image)
            PaletteBackdropGradient(palette: palette, topOpacity: topOpacity, midOpacity: midOpacity, lowerOpacity: 0.90)
            if scrim { KimaHeroScrim() }
        }
        .task(id: coverId) {
            guard let id = coverId,
                  let url = CoverArtURL.url(base: env.server, coverId: id, size: 300) else {
                image = nil; return
            }
            image = try? await ImageCache.shared.fetch(url: url)
        }
    }
}

/// Dark-dominant scrim over a hero backdrop: keeps the bars and hero text legible when the cover is pale (a near-white
/// sleeve or photo). Only the backdrop darkens; the art and text sit above it, and the palette tint still reads through.
struct KimaHeroScrim: View {
    var body: some View {
        LinearGradient(
            colors: [KimaColor.base.opacity(0.62), KimaColor.base.opacity(0.38), KimaColor.base.opacity(0.90)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// A hero's art, heavily blurred over the page colour and fading through `wash` to it (playlists). Opaque at the top,
/// so the art's colour, not the screen ground, reaches the top edge. While the art loads, or if it fails, the cover
/// placeholder's colour stands in; with no art it is the page colour. `authenticated`: the URL is on the user's
/// server, so the request carries the login.
struct KimaHeroArtBackdrop: View {
    let imageURL: URL?
    var authenticated = true
    var wash: Color? = nil

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            KimaColor.base
            if imageURL != nil {
                Group {
                    if let shown = image ?? imageURL.flatMap({ ImageCache.shared.cachedImage(for: $0) }) {
                        KimaPreblurredImage(image: shown, radius: 40)
                    } else {
                        KimaColor.surface
                    }
                }
                .opacity(0.5)
                .overlay(LinearGradient(colors: [.clear] + (wash.map { [$0] } ?? []) + [KimaColor.base],
                                        startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: imageURL) {
            guard let url = imageURL else { image = nil; return }
            image = try? await ImageCache.shared.fetch(url: url, authenticated: authenticated)
        }
    }
}

extension View {
    /// Detail-page hero content: pads it clear of the status bar and the back button.
    func kimaHeroPadding(topInset: CGFloat) -> some View {
        padding(.horizontal, KimaSpacing.lg)
            .padding(.top, topInset + KimaSpacing.xl)
            .padding(.bottom, KimaSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// For a detail page's scroll view (ignoring the top safe area): `backdrop` runs from the top of the screen down to
    /// `heroHeight`, fading into the ground over its lower half, scrolls away with the hero and stretches on pull-down.
    /// The system top scroll-edge effect is off (it would dim the colour); a light dark wash keeps the status bar and
    /// back button legible on pale covers. `columnBleed` widens the backdrop past the readable column.
    func kimaHeroGround<Backdrop: View>(heroHeight: CGFloat, columnBleed: Bool = false,
                                        @ViewBuilder backdrop: () -> Backdrop) -> some View {
        modifier(KimaHeroGround(heroHeight: heroHeight, columnBleed: columnBleed, backdrop: backdrop()))
    }

    /// Widens a hero backdrop past the page's readable-width column (`kimaReadableWidth`) out to the screen
    /// edges, so on iPad the art runs full width with no hard sides while the content stays in the column.
    /// No change when the screen is no wider than the column (iPhone).
    func kimaColumnBleed() -> some View {
        modifier(KimaColumnBleed())
    }
}

private struct KimaHeroGround<Backdrop: View>: ViewModifier {
    let heroHeight: CGFloat
    let columnBleed: Bool
    let backdrop: Backdrop

    /// The scroll position, written by the scroll view and read only by `HeroGroundLayer`, so scrolling updates that
    /// layer alone: this modifier, the page and the backdrop's own content are not rebuilt per frame.
    @State private var scroll = HeroScroll()

    func body(content: Content) -> some View {
        content
            .modifier(HiddenTopScrollEdge())
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                min(geo.contentOffset.y + geo.contentInsets.top, heroHeight)
            } action: { [scroll] _, value in
                scroll.scrolled = value
            }
            .kimaScrollTopGround()
            .background(alignment: .top) {
                Group {
                    if columnBleed {
                        HeroGroundLayer(scroll: scroll, heroHeight: heroHeight, backdrop: backdrop).kimaColumnBleed()
                    } else {
                        HeroGroundLayer(scroll: scroll, heroHeight: heroHeight, backdrop: backdrop)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
    }
}

/// Points a hero page has scrolled from rest (negative while pulled down), held at the hero's height once the
/// backdrop is off screen.
@MainActor
@Observable
private final class HeroScroll {
    var scrolled: CGFloat = 0
}

/// The hero backdrop, moved up with the page and stretched on a pull-down.
private struct HeroGroundLayer<Backdrop: View>: View {
    let scroll: HeroScroll
    let heroHeight: CGFloat
    let backdrop: Backdrop

    @Environment(\.kimaChromeExtent) private var extent

    var body: some View {
        let scrolled = scroll.scrolled
        backdrop
            .frame(height: max(0, heroHeight + max(0, -scrolled)))
            .overlay(alignment: .top) {
                LinearGradient(colors: [KimaColor.base.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: extent.top + KimaLayout.topChromeHeight)
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0.5), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .offset(y: -max(0, scrolled))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct HiddenTopScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}

private struct KimaColumnBleed: ViewModifier {
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content.padding(.horizontal, -KimaLayout.columnBleed(viewport: env.viewportWidth))
    }
}
