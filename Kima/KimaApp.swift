import SwiftUI
import UIKit

/// App entry point. Shows the connect-to-server flow until a session exists, then the main shell.
@main
struct KimaApp: App {
    // Vends the CarPlay scene configuration (SwiftUI apps have no scene delegate of their own,
    // and the plist-only wiring lets the CarPlay delegate get dead-stripped). See KimaAppDelegate.
    @UIApplicationDelegateAdaptor(KimaAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Deep link state

    /// Validated share token from a kima://share/<token> deep link. Drives the window-level
    /// SharedContentView sheet. We hold this here (not in NavigationRouter) so it can be
    /// presented before or after authentication without AppEnvironment access.
    @State private var pendingShareToken: String? = nil

    /// Server base URL read from UserDefaults — the same key used by SessionStore.
    /// Present only after the user has completed the connect flow.
    @AppStorage("kima.serverURL") private var storedServerURL: String = ""

    init() {
        // Purge any Keychain items that survived a prior uninstall before any auth read occurs.
        // iOS does not clear Keychain on uninstall; UserDefaults is cleared, so we use a sentinel
        // to detect a fresh install and call clearAll() exactly once.
        KeychainStore.wipeStaleCredentialsOnFirstInstall()

        // The vibe map's five render pipeline states, built on a utility queue while the launch
        // animation runs so opening the map does not pay five pipeline compiles on the main
        // thread. Fire-and-forget: if the map opens before this finishes, the renderer builds
        // its own states exactly as it did before.
        VibeMapPrewarm.start()

        // MARK: Navigation bar appearance — white, SF-heavy large title, transparent base.
        // All three slots configured so the bar looks right in every scroll state.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        // Titles are pure white.
        let titleColor = UIColor.white
        // Heavy SF large title (web parity); semibold inline title.
        let largeTitleFont = UIFont.systemFont(ofSize: 28, weight: .heavy)
        let sfInline = UIFont.systemFont(ofSize: 17, weight: .semibold)
        appearance.largeTitleTextAttributes = [
            .foregroundColor: titleColor,
            .font: largeTitleFont
        ]
        appearance.titleTextAttributes = [
            .foregroundColor: titleColor,
            .font: sfInline
        ]
        let bar = UINavigationBar.appearance()
        bar.standardAppearance  = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance   = appearance

        #if DEBUG
        // On-device AI smoke test — proves FoundationModels actually runs on this machine.
        // Detached (not tied to any view's lifecycle) so it fires exactly once at true process
        // launch, independent of the sign-in flow; DEBUG-only so Release builds never pay for
        // it. See KimaIntelligence.runLaunchSmokeTest() for what it logs and where.
        Task.detached(priority: .utility) {
            await KimaIntelligence.runLaunchSmokeTest()
        }
        // Listen-meter math self-check — greppable `[ListenMeter] PASS/FAIL` lines in the
        // simulator console. See ListenMeter.swift.
        ListenMeter.runLaunchSelfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .overlay {
                    // Privacy cover: iOS snapshots the frontmost window when the scene transitions
                    // away from .active (the switcher-card capture moment). Cover for both .inactive
                    // and .background so the snapshot never captures live content. Removed completely
                    // when the scene returns to .active — no residual dimming or interaction block.
                    if scenePhase != .active {
                        ZStack {
                            KimaColor.base.ignoresSafeArea()
                            KimaMark()
                                .frame(width: 120, height: 120)
                        }
                        .ignoresSafeArea()
                    }
                }
                // MARK: - Deep link handler (kima://share/<token>)
                .onOpenURL { url in
                    if let token = Self.validateShareDeepLink(url) {
                        pendingShareToken = token
                    } else if let route = parsePlayerRoute(from: url) {
                        // kima://queue · kima://sleep-timer (PlayerRoute.swift). Routed via
                        // the shared router — onOpenURL can fire before env injection.
                        PlayerRouteRouter.shared.request(route)
                    }
                    // All other kima:// URLs stay silently ignored — no path-injection risk.
                }
                // Window-level share sheet — can fire before or after authentication.
                .sheet(
                    isPresented: Binding(
                        get: { pendingShareToken != nil },
                        set: { if !$0 { pendingShareToken = nil } }
                    )
                ) {
                    if let token = pendingShareToken, let base = URL(string: storedServerURL), !storedServerURL.isEmpty {
                        SharedContentView(shareToken: token, serverBaseURL: base)
                    } else {
                        // A share link opened before a server is configured (fresh install):
                        // explain, rather than presenting a blank sheet.
                        VStack(spacing: KimaSpacing.md) {
                            Image(systemName: "link.badge.exclamationmark")
                                .font(.system(size: 36, weight: .light))
                                .foregroundStyle(KimaColor.textMuted)
                            Text("connect to your server first, then open the link again.")
                                .font(KimaType.body)
                                .foregroundStyle(KimaColor.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, KimaSpacing.xxl)
                            Button("close") { pendingShareToken = nil }
                                .font(KimaType.caption)
                                .foregroundStyle(KimaColor.brand)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AmbientFieldBackdrop(palette: nil).ignoresSafeArea())
                    }
                }
        }
    }

    // MARK: - Deep link validation

    /// Parses and validates a kima://share/<token> URL: scheme "kima", host "share", exactly one path
    /// segment, token base64url [A-Za-z0-9-_] of 16–64 chars. Anything else is silently dropped; no
    /// server/host is ever taken from a deep link (injection prevention), and query/fragment are ignored.
    private static func validateShareDeepLink(_ url: URL) -> String? {
        guard url.scheme == "kima" else { return nil }
        guard url.host() == "share" else { return nil }

        // A legitimate base64url token never needs percent-encoding — reject any encoded path
        // outright so no %2F / %2E trickery can reach (and be normalised by) the decode below.
        guard !url.path(percentEncoded: true).contains("%") else { return nil }

        // path(percentEncoded: false) = "/<token>" for kima://share/<token>
        let rawPath = url.path(percentEncoded: false)
        guard rawPath.hasPrefix("/") else { return nil }
        let token = String(rawPath.dropFirst())

        // No sub-paths: token must not contain "/"
        guard !token.contains("/") else { return nil }

        // Length bounds: 16–64 characters
        guard token.count >= 16, token.count <= 64 else { return nil }

        // Strict base64url charset: A-Z a-z 0-9 - _
        // Anything outside this set (= pad chars, ., /, path-traversal, etc.) is rejected.
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        )
        guard token.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

        return token
    }
}
