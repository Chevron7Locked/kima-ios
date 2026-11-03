import SwiftUI

// MARK: - Mini-player clearance

/// How much vertical room the iPhone bottom unit takes above the tab bar right now: the mini-player
/// card's measured height and the gap under it (only while the card shows), plus the bottom ground's
/// fade above. The shell publishes it; it is 0 on iPad.
private struct MiniPlayerFootprintKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var miniPlayerFootprint: CGFloat {
        get { self[MiniPlayerFootprintKey.self] }
        set { self[MiniPlayerFootprintKey.self] = newValue }
    }
}

private struct MiniPlayerClearanceModifier: ViewModifier {
    @Environment(\.miniPlayerFootprint) private var footprint
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: footprint)
        }
    }
}

extension View {
    /// Reserves the bottom unit's real footprint at the bottom of a scroll screen, so the last row
    /// ends just above the ground's fade.
    func kimaMiniPlayerClearance() -> some View { modifier(MiniPlayerClearanceModifier()) }
}

/// Same reservation as an in-flow spacer, for lists/stacks that can't use a safe-area inset.
struct MiniPlayerClearanceSpacer: View {
    @Environment(\.miniPlayerFootprint) private var footprint
    var body: some View { Color.clear.frame(height: footprint) }
}

// MARK: - Tab bar metrics

/// Where the system tab bar sits, read from the key window's `UITabBarController` public `tabBar`
/// frame. Read on demand (when the card appears, on size-class change), not observed.
@MainActor @Observable
final class TabBarMetrics {
    /// Distance from the window's bottom safe-area edge up to the bar's top edge; nil if unknown.
    private(set) var lift: CGFloat?
    /// The window's top and bottom safe-area insets (status bar, home indicator); 0 until read.
    private(set) var windowTop: CGFloat = 0
    private(set) var windowBottom: CGFloat = 0

    func refresh() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else {
            return set(nil)
        }
        if windowTop != window.safeAreaInsets.top { windowTop = window.safeAreaInsets.top }
        if windowBottom != window.safeAreaInsets.bottom { windowBottom = window.safeAreaInsets.bottom }
        guard let bar = Self.findTabBar(in: window.rootViewController),
              !bar.isHidden, bar.alpha > 0.01, bar.window != nil, let host = bar.superview else {
            return set(nil)
        }
        let frame = host.convert(bar.frame, to: window)
        let lift = window.bounds.height - window.safeAreaInsets.bottom - frame.minY
        set(lift > 0 && lift < 200 ? lift : nil)
    }

    private func set(_ lift: CGFloat?) {
        if self.lift != lift { self.lift = lift }
    }

    private static func findTabBar(in vc: UIViewController?) -> UITabBar? {
        guard let vc else { return nil }
        if let tab = vc as? UITabBarController { return tab.tabBar }
        for child in vc.children { if let found = findTabBar(in: child) { return found } }
        return findTabBar(in: vc.presentedViewController)
    }
}
