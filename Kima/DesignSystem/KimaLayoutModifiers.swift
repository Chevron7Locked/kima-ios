import SwiftUI

extension View {
    /// Makes the view tappable across at least 44x44pt without changing how it looks.
    /// By default the layout frame grows to 44pt (right for a small icon or label alone in a
    /// control). Pass `growsLayout: false` to extend only the tappable area into the
    /// surrounding space, leaving the view's layout size untouched.
    func kimaHitTarget(growsLayout: Bool = true) -> some View {
        modifier(KimaHitTargetModifier(growsLayout: growsLayout))
    }
}

extension View {
    /// Caps the content column at `KimaLayout.readableWidth` on wide screens (iPad); a no-op on
    /// iPhone. Follow with `.frame(maxWidth: .infinity)` to center the capped column.
    func kimaReadableWidth(alignment: Alignment = .center) -> some View {
        frame(maxWidth: KimaLayout.readableWidth, alignment: alignment)
    }
}

private struct KimaHitTargetModifier: ViewModifier {
    let growsLayout: Bool
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        if growsLayout {
            content
                .frame(minWidth: KimaLayout.minTouchTarget, minHeight: KimaLayout.minTouchTarget)
                .contentShape(Rectangle())
        } else {
            let dx = max(0, (KimaLayout.minTouchTarget - size.width) / 2)
            let dy = max(0, (KimaLayout.minTouchTarget - size.height) / 2)
            content
                .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
                .padding(.horizontal, dx)
                .padding(.vertical, dy)
                .contentShape(Rectangle())
                .padding(.horizontal, -dx)
                .padding(.vertical, -dy)
        }
    }
}
