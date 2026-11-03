import SwiftUI

extension AppShellView {
    /// Core TabView: five tabs (`AppTab`), one under iOS's auto-"More"-collapse threshold. Selection binds to
    /// `env.router.selectedTab` so deep links (Activity sheet to Library tab) need no @State mirror.
    var baseTabView: some View {
        @Bindable var router = env.router
        return TabView(selection: $router.selectedTab) {
            HomeView(selectedTab: $router.selectedTab)
                .kimaBottomGround()
                .tabItem { Label("home", systemImage: "house.fill") }
                .tag(AppTab.home)

            LibraryView()
                .kimaBottomGround()
                .tabItem { Label("library", systemImage: "music.note.list") }
                .tag(AppTab.library)

            AudiobooksLibraryView()
                .kimaBottomGround()
                .tabItem { Label("audiobooks", systemImage: "headphones") }
                .tag(AppTab.audiobooks)

            PodcastsLibraryView()
                .kimaBottomGround()
                .tabItem { Label("podcasts", systemImage: "mic") }
                .tag(AppTab.podcasts)

            MoreView(host: host, onSignOut: onSignOut, onChangeServer: onChangeServer)
                .kimaBottomGround()
                .tabItem { Label("more", systemImage: "ellipsis.circle") }
                .tag(AppTab.more)
        }
        // Compact width only: regular width (iPad) renders `RegularShellView` instead. The
        // mini-player overlay, bell, and toast layers are in a separate ZStack.
        .tabViewStyle(.sidebarAdaptable)
        .tint(KimaColor.brand)
        // Transparent tab bar so ambient background field flows under it (iOS 18+).
        .toolbarBackgroundVisibility(.hidden, for: .tabBar)
        .sensoryFeedback(.selection, trigger: router.selectedTab)

    }
}
