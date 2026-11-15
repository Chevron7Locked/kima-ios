import SwiftUI

/// The alert for a pinned self-signed certificate that changed (`ServerTrustState.shown`).
/// "trust the new certificate" forgets the old pin so the next connection pins the new key; it is
/// offered only when the key changed. "cancel" keeps blocking that server. Changes for several
/// hosts show one after another.
///
/// Every surface binds the one injected state. A sheet covers alert attachments below it, so a
/// sheet that must reach the user while up carries its own copy (see `DevicePairingSheet`) with
/// `aboveSheet: true`; while such a copy lives, the root-side copy goes quiet — the lease is the
/// state's (`ServerTrustState.canPresent`), and nobody tracks who is active. Answering anywhere
/// settles it everywhere.
struct CertificateChangedAlert: ViewModifier {
    /// This copy presents over sheets: it is mounted inside sheet content. Intrinsic position,
    /// not coordination — the dynamic "who may present right now" lives in the shared state.
    var aboveSheet = false

    @Environment(ServerTrustState.self) private var trust

    func body(content: Content) -> some View {
        content.alert(
            "security certificate changed",
            isPresented: isPresented,
            presenting: trust.shown
        ) { change in
            // Buttons only act; closing the alert goes through `isPresented`, once per alert.
            if change.keyChanged {
                Button("trust the new certificate", role: .destructive) {
                    trust.trust(host: change.host)
                }
            }
            Button("cancel", role: .cancel) {}
        } message: { change in
            Text("the security certificate for \(change.host) changed. if you did not update your server, someone may be intercepting this connection.")
        }
        .onAppear { trust.attachAlert(overlay: aboveSheet) }
        .onDisappear { trust.detachAlert(overlay: aboveSheet) }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { trust.canPresent(overlay: aboveSheet) },
            set: { if !$0, trust.canPresent(overlay: aboveSheet) { trust.dismissShown() } }
        )
    }
}
