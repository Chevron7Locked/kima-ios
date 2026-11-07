import SwiftUI

/// The top-level gate: switches on SessionStore.phase between the splash, the connect flow, and the authenticated
/// shell. It is the only view KimaApp mounts. `AppEnvironment` is built the first time the phase becomes
/// `.authenticated` (from the stored server URL), injected into `AppShellView`, and cleared on sign-out.
struct RootView: View {
    @State private var session = SessionStore()
    @State private var appEnv: AppEnvironment?
    @State private var pairing: PresentedPairing?
    private let pairingRouter = DevicePairingRouter.shared

    /// The link-a-device request being shown. A new id each time so a second scan reopens the sheet.
    private struct PresentedPairing: Identifiable {
        let id = UUID()
        let request: DevicePairingRequest
    }

    var body: some View {
        Group {
            switch session.phase {
            // Note: .preferredColorScheme(.dark) is applied to the Group below so it covers
            // every branch — splash, connect, and the authenticated shell — making all system
            // chrome (nav bar titles, tab bar, system sheets) render in dark mode on every screen.
            case .launching:
                LaunchSplashView()
                    .task { await session.resume() }

            case .authenticated(let host):
                if let env = appEnv {
                    AppShellView(host: host, onSignOut: {
                        Task { await session.signOut() }
                    }, onChangeServer: { session.changeServer() })
                    .environment(env)
                    .environment(env.player)  // PlaybackController for all tabs + mini-player
                    .tint(KimaColor.textPrimary)
                } else {
                    // Brief base-color frame while the environment is being built via onChange.
                    KimaColor.base.ignoresSafeArea()
                }

            case .unreachable(let host, let serverError):
                // Stored session, but the server didn't answer at launch (offline / moved IP) or
                // answered with an error. A real gate with Retry + Change-address instead of a broken shell.
                ServerUnreachableView(
                    host: host,
                    serverError: serverError,
                    onRetry: { await session.resume() },
                    onChangeServer: { session.changeServer() }
                )

            case .unauthenticated:
                RootFlowView(onAuthenticated: { session.didAuthenticate() })
            }
        }
        #if DEBUG
        // Screenshot harness: -kima-open signin overlays the real unauthenticated flow on top
        // of the shell (session untouched). RootFlowView auto-advances to SignInView itself.
        .overlay {
            if DebugDeepLink.requested == "signin" || DebugDeepLink.requested == "create" {
                RootFlowView(onAuthenticated: {})
            }
        }
        #endif
        .preferredColorScheme(.dark)
        // Link a device (kima://link or "scan qr code"): here because it needs the session and works from any screen.
        .sheet(item: $pairing) { item in
            DevicePairingSheet(session: session, request: item.request) { pairing = nil }
        }
        .onChange(of: pairingRouter.pending) { _, _ in presentPairingRequest() }
        .onAppear { presentPairingRequest() }
        // Over every phase: a changed certificate first shows up on sign-in or the can't-reach gate.
        .modifier(CertificateChangedAlert(isActive: pairing == nil))
        // Cap Dynamic Type at accessibility2 to protect dense layouts — the mini-player chrome,
        // Vibe Map node labels, and large display headers at accessibility3–5 would overflow
        // their containers. accessibility2 is still substantially larger than xxxLarge and covers
        // the vast majority of accessibility needs.
        .dynamicTypeSize(.xSmall ... .accessibility2)
        .animation(.easeInOut, value: session.phase)
        .onChange(of: session.phase) { _, newPhase in
            switch newPhase {
            case .authenticated:
                // Build once per session; guard prevents a redundant alloc on spurious re-fires.
                guard appEnv == nil else { return }
                // A second iPad window joins the live session instead of starting a second player.
                appEnv = CarPlayLink.shared.environment ?? makeAppEnvironment()
                // Share the SAME env (one PlaybackController) with the CarPlay scene, if any.
                CarPlayLink.shared.publish(appEnv)
            case .unauthenticated:
                // Stop the SSE stream and the playback-state poll before releasing the env
                // (Swift-6 @MainActor deinit can't).
                appEnv?.events.teardown()
                appEnv?.sync.stop()
                // Stop minting stream tickets ahead of taps: the env is about to be released and
                // the app is signed out, so there is no session left to warm.
                appEnv?.player.stopKeepingStreamTicketWarm()
                // Clear so the next login gets a fresh client with the (possibly new) credential.
                appEnv = nil
                CarPlayLink.shared.publish(nil)
            case .launching, .unreachable:
                break
            }
        }
    }

    private func presentPairingRequest() {
        if let request = pairingRouter.take() { pairing = PresentedPairing(request: request) }
    }

    /// Builds the shell's `AppEnvironment` from the address this process talks to
    /// (`ServerURLStore.current`, so the DEBUG test override is honoured). Returns nil only if the
    /// address is missing, which cannot happen while the session is `.authenticated`
    /// (SessionStore.didAuthenticate() guards on the URL). If it somehow does, the base-color
    /// placeholder stays visible until the user signs out.
    private func makeAppEnvironment() -> AppEnvironment? {
        guard let urlString = ServerURLStore.current,
              let url = URL(string: urlString) else { return nil }
        return AppEnvironment(server: KimaServer(baseURL: url))
    }
}

#Preview {
    RootView()
}
