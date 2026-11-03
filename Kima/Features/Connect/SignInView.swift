import SwiftUI

/// Connect to an existing account: password sign-in (with 2FA) or a device-link pairing code.
/// Built on the shared KimaDesign components (warm segmented control, field style, primary button).
struct SignInView: View {
    let host: String
    var onSignedIn: () -> Void
    @State private var vm: SignInViewModel
    @FocusState private var focused: Field?

    enum Field: Hashable { case username, password, twoFactor, pairing }

    init(server: KimaServer, host: String, onSignedIn: @escaping () -> Void) {
        self.host = host
        self.onSignedIn = onSignedIn
        _vm = State(initialValue: SignInViewModel(server: server))
    }

    var body: some View {
        ConnectFormPage(title: vm.method == .password ? "sign in" : "pair this device",
                        subtitle: "connected to \(host)", error: failureMessage) {
            KimaSegmented(
                options: [(.password, "password"), (.pairing, "pairing code")],
                selection: $vm.method
            )

            fields

            KimaPrimaryButton(title: buttonTitle, isLoading: vm.phase == .working) {
                focused = nil
                Task { await vm.submit() }
            }
            .disabled(!vm.canSubmit)
        }
        .onChange(of: vm.phase) { _, phase in
            if phase == .success { onSignedIn() }
        }
    }

    private var failureMessage: String? {
        if case let .failed(message) = vm.phase { return message }
        return nil
    }

    @ViewBuilder private var fields: some View {
        switch vm.method {
        case .password:
            TextField("", text: $vm.username, prompt: .kimaPrompt("username"))
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .username)
                .submitLabel(.next)
                .onSubmit { Task { await vm.submit() } }
                .kimaField(focused: focused == .username)

            SecureField("", text: $vm.password, prompt: .kimaPrompt("password"))
                .textContentType(.password)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await vm.submit() } }
                .kimaField(focused: focused == .password)

            if vm.needs2FA {
                TextField("", text: $vm.twoFactorCode, prompt: .kimaPrompt("2-factor or recovery code"))
                    .textContentType(.oneTimeCode)
                    .keyboardType(.asciiCapable)                 // TOTP digits AND hex recovery codes
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .twoFactor)
                    .submitLabel(.go)
                    .onSubmit { Task { await vm.submit() } }
                    .kimaField(focused: focused == .twoFactor)
                    .privacySensitive()                          // redact under .privacy redaction
            }
        case .pairing:
            TextField("", text: $vm.pairingCode, prompt: .kimaPrompt("pairing code"))
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focused, equals: .pairing)
                .submitLabel(.go)
                .onSubmit { Task { await vm.submit() } }
                .kimaField(focused: focused == .pairing)
                .privacySensitive()                              // pairing code grants permanent API key — redact

            Text("get a code on the kima website under settings → link device.")
                .font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
        }
    }

    private var buttonTitle: String {
        if vm.phase == .working { return "connecting…" }
        return vm.method == .password ? "sign in" : "pair device"
    }
}

#Preview {
    NavigationStack {
        SignInView(
            server: KimaServer(baseURL: URL(string: "https://kima.example.com")!),
            host: "kima.example.com",
            onSignedIn: {}
        )
    }
}
