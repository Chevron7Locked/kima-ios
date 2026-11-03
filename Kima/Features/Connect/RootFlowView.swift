import SwiftUI

/// The unauthenticated flow: enter server → (sign in | create account → sync) → authenticated.
/// Owns the NavigationStack path so child screens just append routes.
/// On successful sign-in or scan completion, calls `onAuthenticated` so `RootView` can switch phase.
enum ConnectRoute: Hashable {
    case signIn(serverURL: String, host: String)
    case createAccount(serverURL: String, host: String)
    case syncProgress(serverURL: String, host: String)
}

struct RootFlowView: View {
    var onAuthenticated: () -> Void

    @State private var path: [ConnectRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ServerConnectView { serverURL, host, status in
                path.append(status.hasAccount
                    ? .signIn(serverURL: serverURL, host: host)
                    : .createAccount(serverURL: serverURL, host: host))
            }
            .navigationDestination(for: ConnectRoute.self, destination: destination)
            #if DEBUG
            // Screenshot deep-link (-kima-open signin): auto-advance connect → sign-in so the
            // auth screens can be captured without logging the real session out.
            .task {
                switch DebugDeepLink.requested {
                case "signin":
                    try? await Task.sleep(for: .milliseconds(700))
                    path.append(.signIn(serverURL: "https://kima.example.com", host: "kima.example.com"))
                case "create":
                    try? await Task.sleep(for: .milliseconds(700))
                    path.append(.createAccount(serverURL: "https://kima.example.com", host: "kima.example.com"))
                default: break
                }
            }
            #endif
        }
        .tint(KimaColor.textPrimary)   // ink back button / nav accents
    }

    @ViewBuilder
    private func destination(for route: ConnectRoute) -> some View {
        switch route {
        case let .signIn(serverURL, host):
            if let server = server(from: serverURL) {
                SignInView(server: server, host: host) { onAuthenticated() }
            } else {
                invalidServer
            }

        case let .createAccount(serverURL, host):
            if let server = server(from: serverURL) {
                CreateAccountView(server: server, host: host) {
                    path.append(.syncProgress(serverURL: serverURL, host: host))
                }
            } else {
                invalidServer
            }

        case let .syncProgress(serverURL, host):
            if let server = server(from: serverURL) {
                SyncProgressView(server: server, host: host) { onAuthenticated() }
            } else {
                invalidServer
            }
        }
    }

    private func server(from urlString: String) -> KimaServer? {
        guard let url = URL(string: urlString) else { return nil }
        return KimaServer(baseURL: url)
    }

    private var invalidServer: some View {
        ZStack {
            KimaColor.base.ignoresSafeArea()
            Text("that server address couldn't be used.")
                .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
        }
    }
}

#Preview {
    RootFlowView(onAuthenticated: {})
}
