import SwiftUI

/// The alert for a pinned self-signed certificate that changed (`ServerTrustState.shown`).
/// "trust the new certificate" forgets the old pin so the next connection pins the new key; it is
/// offered only when the key changed. "cancel" keeps blocking that server. Changes for several
/// hosts show one after another.
struct CertificateChangedAlert: ViewModifier {
    private var state: ServerTrustState { .shared }

    func body(content: Content) -> some View {
        content.alert(
            "security certificate changed",
            isPresented: isPresented,
            presenting: state.shown
        ) { change in
            // Buttons only act; closing the alert goes through `isPresented`, once per alert.
            if change.keyChanged {
                Button("trust the new certificate", role: .destructive) {
                    ServerTrustCoordinator.shared.trustNewCertificate(host: change.host)
                }
            }
            Button("cancel", role: .cancel) {}
        } message: { change in
            Text("the security certificate for \(change.host) changed. if you did not update your server, someone may be intercepting this connection.")
        }
        #if DEBUG
        // Screenshot hook: -kima-fake-cert-changed <host>[,<host>…] raises the alerts without a real certificate.
        .task {
            guard let hosts = DebugDeepLink.launchArgValue("-kima-fake-cert-changed") else { return }
            try? await Task.sleep(for: .seconds(1))
            for host in hosts.split(separator: ",") { state.report(host: String(host), keyChanged: true) }
        }
        #endif
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { state.shown != nil },
            set: { if !$0 { state.dismissShown() } }
        )
    }
}
