import SwiftUI

/// First real screen: enter your Kima server address, validate it, branch to sign-in vs create-account.
/// Built entirely on the KimaDesign tokens; handles idle / checking / error / found states.
struct ServerConnectView: View {
    /// Invoked once the server validates; the parent navigates to sign-in or create-account.
    let onFound: (_ serverURL: String, _ host: String, _ status: OnboardingStatus) -> Void

    @State private var vm = ConnectViewModel()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            AmbientFieldBackdrop(palette: nil).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KimaSpacing.xl) {
                    wordmark.padding(.top, KimaSpacing.huge)

                    VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                        Text("connect to your server")
                            .font(KimaType.pageTitle)
                            .foregroundStyle(KimaColor.textPrimary)
                            .tracking(-0.4)
                        Text("enter the web address of your kima server.")
                            .font(KimaType.body)
                            .foregroundStyle(KimaColor.textSecondary)
                    }

                    urlField
                    connectButton
                    resultCard

                    Spacer(minLength: KimaSpacing.huge)
                }
                .padding(.horizontal, KimaSpacing.lg)
                .kimaReadableWidth()
                .frame(maxWidth: .infinity)
            }
            .kimaKeyboardSafeCanvas()
        }
        .onChange(of: vm.phase) { _, newPhase in
            if case let .found(status, host) = newPhase, let url = vm.resolvedURL {
                onFound(url, host, status)
            }
        }
        .confirmationDialog(
            "connection not encrypted",
            isPresented: $vm.showsInsecureAlert,
            titleVisibility: .visible
        ) {
            Button("connect anyway", role: .destructive) {
                Task { await vm.confirmInsecureConnection() }
            }
            Button("cancel", role: .cancel) { }
        } message: {
            Text("this server uses http, so your password and data are sent unencrypted. others on your network could see them.")
        }
    }

    private var wordmark: some View {
        HStack(spacing: KimaSpacing.md) {
            KimaMark()                        // living spectrum waveform mark
                .frame(width: 30, height: 30)
            Text("kima").font(KimaType.wordmark(28)).foregroundStyle(KimaColor.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("kima")
    }

    private var urlField: some View {
        TextField("", text: $vm.urlText, prompt: .kimaPrompt("kima.yourdomain.com"))
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($fieldFocused)
            .submitLabel(.go)
            .onSubmit { submit() }
            .kimaField(focused: fieldFocused)
            .accessibilityLabel("server web address")
            .accessibilityHint("enter your server address, then tap connect")
    }

    private var connectButton: some View {
        KimaPrimaryButton(
            title: vm.phase == .checking ? "checking…" : "connect",
            isLoading: vm.phase == .checking,
            systemImage: "arrow.right",
            action: submit
        )
        .disabled(!vm.canSubmit)
        .accessibilityLabel("connect to server")
    }

    @ViewBuilder private var resultCard: some View {
        switch vm.phase {
        case .failed(let message):
            KimaErrorCard(message: message)
        case .found(let status, let host):
            KimaInfoCard(glyph: "checkmark.circle.fill", tint: KimaColor.positive) {
                VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                    Text("connected to \(host)")
                        .font(KimaType.headline).foregroundStyle(KimaColor.textPrimary)
                    Text(status.hasAccount
                         ? "next: sign in to your account."
                         : "next: create the first account on this server.")
                        .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                }
            }
        default:
            EmptyView()
        }
    }

    private func submit() {
        fieldFocused = false
        Task { await vm.check() }
    }
}

#Preview {
    ServerConnectView { _, _, _ in }
}
