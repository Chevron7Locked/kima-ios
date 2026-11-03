import SwiftUI
import Observation

// MARK: - ViewModel

/// Drives the first-account registration flow: POST /api/onboarding/register →
/// store JWT → POST /api/onboarding/complete. On success, signals `.registered`
/// so the view navigates to `SyncProgressView`.
@MainActor
@Observable
final class CreateAccountViewModel {
    enum Phase: Equatable {
        case idle, working, failed(String), registered
    }

    let server: KimaServer
    var username: String = ""
    var password: String = ""
    var confirmPassword: String = ""
    var phase: Phase = .idle

    init(server: KimaServer) { self.server = server }

    var canSubmit: Bool {
        !username.isEmpty && !password.isEmpty && !confirmPassword.isEmpty && phase != .working
    }

    func submit() async {
        guard phase != .working else { return }
        if password.count < 6 {
            phase = .failed("password must be at least 6 characters.")
            return
        }
        if password != confirmPassword {
            phase = .failed("passwords don't match.")
            return
        }
        phase = .working
        let client = KimaAPIClient(server: server)
        do {
            let response = try await client.onboardingRegister(username: username, password: password)
            guard let token = response.token else {
                // 200 but no token — the account may have been created server-side without a
                // session. Point the user at sign-in rather than a dead-end "unexpected response".
                phase = .failed("your account may have been created, but sign-in failed. go back and sign in.")
                return
            }
            guard KeychainStore.setCredential(token, for: KeychainStore.accessToken, server: server) else {
                phase = .failed("couldn't securely save your sign-in. please try again.")
                return
            }
            KeychainStore.clearCredentials(except: [KeychainStore.accessToken])   // drops any other server's login
            // Persist server URL so SessionStore.didAuthenticate() can read it after sync.
            ServerURLStore.setStored(server.baseURL.absoluteString)
            // Mark onboarding complete (best-effort — proceed to library scan even if this fails).
            let authedClient = KimaAPIClient(server: server, credential: .jwt(token))
            await authedClient.onboardingComplete()
            phase = .registered
        } catch let error as APIError {
            phase = .failed(error.errorDescription ?? "registration failed.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

// MARK: - View

/// Account-creation screen for a brand-new Kima server (no account exists yet).
/// Performs the real register → complete flow and pushes to `SyncProgressView` on success.
struct CreateAccountView: View {
    let host: String
    var onRegistered: () -> Void
    @State private var vm: CreateAccountViewModel
    @FocusState private var focused: Field?

    enum Field: Hashable { case username, password, confirmPassword }

    init(server: KimaServer, host: String, onRegistered: @escaping () -> Void) {
        self.host = host
        self.onRegistered = onRegistered
        _vm = State(initialValue: CreateAccountViewModel(server: server))
    }

    var body: some View {
        ConnectFormPage(title: "create your account", subtitle: "this will be the admin account for \(host).",
                        error: failureMessage) {
            usernameField
            passwordField
            confirmField
            createButton
        }
        .onChange(of: vm.phase) { _, phase in
            if phase == .registered { onRegistered() }
        }
    }

    // MARK: - Subviews

    private var failureMessage: String? {
        if case let .failed(message) = vm.phase { return message }
        return nil
    }

    private var usernameField: some View {
        TextField("", text: $vm.username, prompt: .kimaPrompt("username"))
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused, equals: .username)
            .submitLabel(.next)
            .onSubmit { focused = .password }
            .kimaField(focused: focused == .username)
            .accessibilityLabel("username")
    }

    private var passwordField: some View {
        SecureField("", text: $vm.password, prompt: .kimaPrompt("password (at least 6 characters)"))
            .textContentType(.newPassword)
            .focused($focused, equals: .password)
            .submitLabel(.next)
            .onSubmit { focused = .confirmPassword }
            .kimaField(focused: focused == .password)
            .accessibilityLabel("password")
    }

    private var confirmField: some View {
        SecureField("", text: $vm.confirmPassword, prompt: .kimaPrompt("confirm password"))
            .textContentType(.newPassword)
            .focused($focused, equals: .confirmPassword)
            .submitLabel(.go)
            .onSubmit {
                focused = nil
                Task { await vm.submit() }
            }
            .kimaField(focused: focused == .confirmPassword)
            .accessibilityLabel("confirm password")
    }

    private var createButton: some View {
        KimaPrimaryButton(
            title: vm.phase == .working ? "creating…" : "create account",
            isLoading: vm.phase == .working,
            systemImage: vm.phase == .working ? nil : "arrow.right"
        ) {
            focused = nil
            Task { await vm.submit() }
        }
        .disabled(!vm.canSubmit)
        .accessibilityLabel("create admin account")
    }
}

#Preview {
    NavigationStack {
        CreateAccountView(
            server: KimaServer(baseURL: URL(string: "https://kima.example.com")!),
            host: "kima.example.com",
            onRegistered: {}
        )
    }
}
