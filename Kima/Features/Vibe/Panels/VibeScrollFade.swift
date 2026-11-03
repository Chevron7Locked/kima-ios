import SwiftUI

/// Fades a scroll view's content out over `length` points at an edge where more is hidden, so a cut
/// row reads as "more this way" instead of a line sliced through its letters.
private struct VibeScrollFade: ViewModifier {
    struct Hidden: Equatable {
        var above = false
        var below = false
    }

    let length: CGFloat
    /// Read only by `VibeScrollFadeMask`, so reaching an edge redraws the mask without re-evaluating the scroll view.
    @State private var state = VibeScrollFadeState()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Hidden.self) { g in
                Hidden(above: g.visibleRect.minY > 0.5, below: g.visibleRect.maxY < g.contentSize.height - 0.5)
            } action: { [state] _, now in state.hidden = now }
            .mask { VibeScrollFadeMask(state: state, length: length) }
    }
}

@MainActor
@Observable
private final class VibeScrollFadeState {
    var hidden = VibeScrollFade.Hidden()
}

private struct VibeScrollFadeMask: View {
    let state: VibeScrollFadeState
    let length: CGFloat

    var body: some View {
        let hidden = state.hidden
        VStack(spacing: 0) {
            LinearGradient(colors: [hidden.above ? .clear : .black, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: length)
            Color.black
            LinearGradient(colors: [.black, hidden.below ? .clear : .black], startPoint: .top, endPoint: .bottom)
                .frame(height: length)
        }
    }
}

/// A list as tall as its rows up to `maxHeight`, scrolling past that with its cut edges faded.
/// `exact` sets that height outright, for a list hanging in a background, where the space offered is
/// smaller than the list.
struct VibeSizedScroll<Content: View>: View {
    var maxHeight: CGFloat = .infinity
    var exact = false
    @ViewBuilder var content: () -> Content

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let height = min(contentHeight, maxHeight)
        ScrollView {
            content()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .vibeScrollFade()
        .frame(height: exact ? height : nil)
        .frame(maxHeight: exact ? nil : height)
    }
}

extension View {
    /// Fades the edges of this scroll view where rows are cut off; see `VibeScrollFade`.
    func vibeScrollFade(_ length: CGFloat = KimaSpacing.xl) -> some View {
        modifier(VibeScrollFade(length: length))
    }
}
