import SwiftUI

/// How far the iPhone shell's floating chrome reaches in from each screen edge: at the top the status bar, at the
/// bottom the home indicator, tab bar and (while it shows) the mini player card. 0 where nothing floats (iPad).
struct KimaChromeExtent: Equatable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
    /// How much of `bottom` is the fade above the solid ground.
    var bottomFade: CGFloat = 0
}

private struct KimaChromeExtentKey: EnvironmentKey {
    static let defaultValue = KimaChromeExtent()
}

extension EnvironmentValues {
    var kimaChromeExtent: KimaChromeExtent {
        get { self[KimaChromeExtentKey.self] }
        set { self[KimaChromeExtentKey.self] = newValue }
    }
}

/// How opaque the bottom ground's page colour is, from the content side down: 0 at the content side, easing to full
/// over `fade` points, then full for the last `solid` points.
/// The ease is weighted toward the edge side, so content is all but gone over the last third of the fade.
private func kimaEdgeStops(solid: CGFloat, fade: CGFloat) -> [(opacity: Double, location: CGFloat)] {
    let end = fade / (solid + fade)
    return [(0, 0), (0.7, end * 0.3), (0.95, end * 0.55), (0.99, end * 0.75), (1, end), (1, 1)]
}

/// Once a page scrolls, content under the status bar is hidden, easing back in over a short soft edge
/// (`KimaLayout.statusBarFade`), so no text sits under the clock; the ground and its glow still show to the top
/// edge, and the floating row below floats over the content. It comes in over the first `topChromeHeight` points
/// of scroll, in 20 steps so scrolling does not redraw it every frame; the page at rest looks unchanged.
private struct ScrollTopGroundModifier: ViewModifier {
    /// Written by the scroll view and read only by `ScrollTopGroundMask`. State on this modifier would re-evaluate the
    /// scroll view on every step through the top band, which on device restarts its bounce at the top edge.
    @State private var scroll = TopGroundScroll()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                let scrolled = geo.contentOffset.y + geo.contentInsets.top
                return (min(1, max(0, scrolled / KimaLayout.topChromeHeight)) * 20).rounded() / 20
            } action: { [scroll] _, value in
                scroll.shown = value
            }
            .mask { ScrollTopGroundMask(scroll: scroll).ignoresSafeArea() }
            #if DEBUG
            .modifier(DebugScrollDown())
            #endif
    }
}

/// How far the status-bar cover has come in: 0 at rest, 1 once the page has scrolled `topChromeHeight` points.
@MainActor
@Observable
private final class TopGroundScroll {
    var shown: CGFloat = 0
}

private struct ScrollTopGroundMask: View {
    let scroll: TopGroundScroll
    @Environment(\.kimaChromeExtent) private var extent

    var body: some View {
        let shown = scroll.shown
        let edge = min(KimaLayout.statusBarFade, extent.top)
        // One structure at every value, so the mask is never swapped for another view mid-scroll.
        VStack(spacing: 0) {
            Color.black.opacity(1 - shown)
                .frame(height: max(0, extent.top - edge))
            // Smoothstep back in, so the content's cut never ends on a visible line.
            LinearGradient(stops: (0...6).map { i -> Gradient.Stop in
                let t = Double(i) / 6
                return .init(color: .black.opacity(1 - shown * (1 - t * t * (3 - 2 * t))), location: t)
            }, startPoint: .top, endPoint: .bottom)
            .frame(height: edge)
            Color.black
        }
    }
}

#if DEBUG
/// Screenshot hook: `-kima-scroll-down [points]` scrolls the page (400pt unless given) once it has loaded, to capture
/// the scrolled top edge.
private struct DebugScrollDown: ViewModifier {
    @State private var position = ScrollPosition()
    private static let distance: CGFloat? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-kima-scroll-down") else { return nil }
        return args.dropFirst(i + 1).first.flatMap(Double.init).map { CGFloat($0) } ?? 400
    }()

    func body(content: Content) -> some View {
        if let distance = Self.distance {
            content
                .scrollPosition($position)
                .task {
                    try? await Task.sleep(for: .seconds(6))
                    position.scrollTo(y: distance)
                }
        } else {
            content
        }
    }
}
#endif

/// The solid page-colour ground under the tab bar and, while it shows, the mini player card, with a short fade above
/// so content dissolves before it reaches them. Each tab draws it over its pages, so it sits under the bar. Takes no taps.
struct KimaBottomGround: View {
    @Environment(\.kimaChromeExtent) private var extent

    var body: some View {
        if extent.bottom > 0 {
            let fade = min(extent.bottom, extent.bottomFade)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ground(solid: extent.bottom - fade, fade: fade).frame(height: extent.bottom)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func ground(solid: CGFloat, fade: CGFloat) -> some View {
        if fade <= 0 {
            KimaColor.base
        } else {
            LinearGradient(
                stops: kimaEdgeStops(solid: solid, fade: fade).map {
                    .init(color: KimaColor.base.opacity($0.opacity), location: $0.location)
                },
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

extension View {
    /// Draws `KimaBottomGround` over a tab's pages (under the tab bar).
    func kimaBottomGround() -> some View { overlay { KimaBottomGround() } }
    /// Apply to a page's vertical `ScrollView` whose content passes under the status bar: once it scrolls, content is hidden under the status bar.
    func kimaScrollTopGround() -> some View { modifier(ScrollTopGroundModifier()) }
}
