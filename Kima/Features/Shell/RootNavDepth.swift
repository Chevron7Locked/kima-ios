import SwiftUI

extension View {
    /// Publishes a tab root's NavigationStack depth to `NavigationRouter.navDepthByTab` so the app-level bell
    /// (AppShellView.bellOverlay) hides while a detail is pushed, and never covers its trailing toolbar. Apply to
    /// the root's `NavigationStack`, passing that stack's `path.count`.
    func publishesNavDepth(tab: AppTab, count: Int, to router: NavigationRouter) -> some View {
        self
            .onAppear { router.navDepthByTab[tab] = count }
            .onChange(of: count) { _, newCount in router.navDepthByTab[tab] = newCount }
    }
}
