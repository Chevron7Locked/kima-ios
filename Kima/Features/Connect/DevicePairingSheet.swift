import SwiftUI

/// Link this device to a server from a link-a-device QR code. One sheet holds every step so the
/// scanner never presents a second sheet.
struct DevicePairingSheet: View {
    let session: SessionStore
    @State private var vm: DevicePairingViewModel
    @Environment(\.dismiss) private var dismiss

    init(session: SessionStore, request: DevicePairingRequest, dismissSheet: @escaping () -> Void) {
        self.session = session
        _vm = State(initialValue: DevicePairingViewModel(
            request: request,
            currentPhase: { session.phase },
            onLinked: { dismissSheet(); session.didAuthenticate() }
        ))
    }

    var body: some View {
        ZStack {
            AmbientFieldBackdrop(palette: nil).ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .onDisappear { vm.cancel() }
        // The alert on RootView cannot show over this sheet, so the sheet carries its own.
        .modifier(CertificateChangedAlert())
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case _ where vm.step == .linked:
            ProgressView().tint(KimaColor.textPrimary)
        case .launching:
            ProgressView().tint(KimaColor.textPrimary)
        case .authenticated:
            message(title: "already signed in",
                    body: "this device is already signed in. sign out first, then scan again.") { closeButton }
        case .unauthenticated, .unreachable:
            switch vm.step {
            case .scanning: scanning
            case .confirm(let link): confirm(link)
            case .waiting: waiting
            case .linked: ProgressView().tint(KimaColor.textPrimary)
            case .failed(let text, let retry): failed(text, retry: retry)
            }
        }
    }

    private var scanning: some View {
        VStack(spacing: KimaSpacing.lg) {
            Text("scan qr code").font(KimaType.pageTitle).foregroundStyle(KimaColor.textPrimary)
            QRScannerView { vm.scanned($0) }
                .clipShape(RoundedRectangle(cornerRadius: KimaRadius.card))
                .frame(maxWidth: 420, maxHeight: 420)
                .aspectRatio(1, contentMode: .fit)
            Text(vm.scanHint ?? "on the kima website, open settings → link a device.")
                .font(KimaType.body)
                .foregroundStyle(vm.scanHint == nil ? KimaColor.textSecondary : KimaColor.danger)
                .multilineTextAlignment(.center)
            closeButton
        }
        .padding(KimaSpacing.xl)
    }

    private func confirm(_ link: DevicePairingLink) -> some View {
        message(title: "link this device", body: nil) {
            Text(SessionStore.displayHost(for: link.server.baseURL, fallback: "this server"))
                .font(KimaType.headline).foregroundStyle(KimaColor.textPrimary)
                .textSelection(.enabled)
            if link.isLoopback {
                KimaErrorCard(message: "this code points at this computer, not your server. open kima on the web using its network address, then scan again.")
            } else {
                Text("only link to a server you know.")
                    .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                if let host = replacedHost(for: link) {
                    Text("this replaces your sign-in for \(host).")
                        .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                }
                if link.usesCleartext, !NetworkTrust.isPrivateHost(link.server.baseURL.host()) {
                    KimaErrorCard(message: "this server uses http, so your data is sent unencrypted.")
                }
                KimaPrimaryButton(title: "link device") { vm.confirm() }
            }
            closeButton
        }
    }

    /// The host of the stored sign-in this link would replace, when it is a different server.
    private func replacedHost(for link: DevicePairingLink) -> String? {
        guard case .unreachable(let host, _) = session.phase,
              host != SessionStore.displayHost(for: link.server.baseURL, fallback: "") else { return nil }
        return host
    }

    private var waiting: some View {
        message(title: "link this device", body: "approve this device on the link page.") {
            ProgressView().tint(KimaColor.textPrimary)
            Button("cancel") { vm.cancel(); dismiss() }
                .font(KimaType.captionStrong).foregroundStyle(KimaColor.textSecondary)
                .frame(minHeight: KimaLayout.minTouchTarget)
        }
    }

    private func failed(_ text: String, retry: DevicePairingLink?) -> some View {
        message(title: "couldn't link", body: nil) {
            KimaErrorCard(message: text)
            if retry != nil {
                KimaPrimaryButton(title: "try again") { vm.retry() }
            } else {
                KimaPrimaryButton(title: "scan again", style: .secondary) { vm.scanAgain() }
            }
            closeButton
        }
    }

    private var closeButton: some View {
        Button("close") { vm.cancel(); dismiss() }
            .font(KimaType.captionStrong).foregroundStyle(KimaColor.textSecondary)
            .frame(minHeight: KimaLayout.minTouchTarget)
    }

    private func message<Extra: View>(title: String, body: String?,
                                      @ViewBuilder extra: () -> Extra) -> some View {
        VStack(spacing: KimaSpacing.lg) {
            Text(title).font(KimaType.pageTitle).foregroundStyle(KimaColor.textPrimary)
            if let body {
                Text(body).font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            extra()
        }
        .padding(KimaSpacing.xl)
        .frame(maxWidth: 480)
    }
}
