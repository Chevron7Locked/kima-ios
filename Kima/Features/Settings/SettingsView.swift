import SwiftUI
import Observation

// Settings. Account + appearance live here; every other section has its own
// file (sign out + delete account in SettingsAccountActions.swift).

// MARK: - SettingsViewModel

@MainActor
@Observable
final class SettingsViewModel {

    // MARK: Account

    var currentUser: KimaUser?
    var isLoadingUser = false

    // MARK: Connection test

    enum ConnectionState: Equatable { case idle, testing, ok, failed }
    var connectionState: ConnectionState = .idle

    // MARK: Storage / cache

    var storageUsedString: String?
    var isClearingCache = false

    // MARK: Delete account

    var isDeletingAccount = false

    // MARK: - Actions

    func loadUser(client: KimaAPIClient) async {
        isLoadingUser = true
        defer { isLoadingUser = false }
        currentUser = try? await client.me()
    }

    func testConnection(client: KimaAPIClient) async {
        connectionState = .testing
        do {
            _ = try await client.onboardingStatus()
            connectionState = .ok
        } catch {
            connectionState = .failed
        }
    }

    /// Measures what "clear image cache" removes: cached cover images and the URL cache.
    func computeStorageUsed() {
        let used = ImageCache.shared.storedBytes + URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
        storageUsedString = ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .file)
    }

    func clearCache() async {
        isClearingCache = true
        defer { isClearingCache = false }
        URLCache.shared.removeAllCachedResponses()
        await ImageCache.shared.clearAll()
        computeStorageUsed()
    }

    /// DELETE /api/auth/account. A 409 "only administrator" error propagates at once; a 409
    /// "concurrent account change" is retried up to three attempts in total.
    func deleteAccount(client: KimaAPIClient) async throws {
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                try await client.deleteAccount()
                return
            } catch {
                guard
                    case let APIError.http(status, body) = error,
                    status == 409,
                    body?.localizedCaseInsensitiveContains("concurrent account change") == true,
                    attempt < maxAttempts
                else { throw error }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
}

// MARK: - SettingsView

/// Real settings screen — 9 sections. Pushed from MoreView's NavigationStack.
struct SettingsView: View {
    let host: String
    let onSignOut: () -> Void
    /// Keeps the stored credential (same path as the can't-reach gate), unlike sign out.
    let onChangeServer: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast

    @State private var vm = SettingsViewModel()
    @Bindable private var prefs = UserPreferences.shared

    var body: some View {
        ZStack {
            KimaScreenGround()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Shared editorial masthead — same primitive as Library/Audiobooks/Podcasts.
                        KimaScreenHeader(title: "settings")

                        #if DEBUG
                        NavigationLink { DesignLabView() } label: {
                            HStack(spacing: KimaSpacing.md) {
                                Image(systemName: "paintpalette.fill").foregroundStyle(.purple)
                                Text("design lab").font(KimaType.body).foregroundStyle(KimaColor.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(KimaColor.textMuted)
                            }
                            .padding(KimaSpacing.lg)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        #endif
                        accountSection
                        ServerSection(
                            host: host,
                            scheme: env.server.baseURL.scheme,
                            connectionState: vm.connectionState,
                            onTestConnection: { Task { await vm.testConnection(client: env.client) } },
                            onChangeServer: onChangeServer
                        )
                        PlaybackSection(prefs: prefs, player: player,
                                        isAdmin: vm.currentUser?.role == "admin")
                        ScrobblingSection()
                        DownloadsSection(
                            storageUsed: vm.storageUsedString,
                            isClearingCache: vm.isClearingCache,
                            onClearCache: { Task { await vm.clearCache() } }
                        )
                        SettingsAboutSection()
                            .id("kimaSettingsAbout")
                        // The exits close the page: sign out, then delete account alone at the very
                        // bottom (each section owns its separation — see SettingsAccountActions).
                        SignOutSection(onSignOut: onSignOut)
                        DangerZoneSection(
                            isDeletingAccount: vm.isDeletingAccount,
                            onDeleteAccount: deleteAccount
                        )
                    }
                    .kimaReadableWidth()
                    .frame(maxWidth: .infinity)
                }
                .kimaScrollTopGround()
                .kimaMiniPlayerClearance()
                #if DEBUG
                // Screenshot hook: `-kima-scroll-about` scrolls to the about rows.
                .task {
                    guard CommandLine.arguments.contains("-kima-scroll-about") else { return }
                    try? await Task.sleep(for: .milliseconds(1500))
                    proxy.scrollTo("kimaSettingsAbout", anchor: .top)
                }
                #endif
            }
        }
        // Nav bar kept (for the automatic back chevron since this is pushed from More's own
        // stack) but emptied — the editorial masthead in the scroll content does the work,
        // matching the Radio/Discover pattern for pushed non-tab-root screens.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.loadUser(client: env.client)
            vm.computeStorageUsed()
        }
    }

    // MARK: - Account section

    private func deleteAccount() {
        Task {
            do {
                try await vm.deleteAccount(client: env.client)
                onSignOut()   // clears session on success, returns to connect flow
            } catch APIError.http(let status, let body) where status == 409 && body?.localizedCaseInsensitiveContains("only administrator") == true {
                toast.show("this is the server's only admin account, so it can't be deleted.", style: .error)
            } catch {
                // Any other failure: say so instead of failing silently.
                toast.show((error as? APIError)?.errorDescription ?? "couldn't delete account. please try again.", style: .error)
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        KimaSectionHeader(title: "account")

        HStack(spacing: KimaSpacing.lg) {
            // Avatar — mood orb with the username's initial
            ZStack {
                // The web's mood orb: two soft mood glows (relaxed, sad) on a deep violet disc.
                Circle()
                    .fill(Color(hex: 0x0A0710))
                    .overlay(RadialGradient(colors: [Color(hex: 0x529796), .clear],
                                            center: UnitPoint(x: 0.36, y: 0.32), startRadius: 0, endRadius: 58 * 0.40))
                    .overlay(RadialGradient(colors: [Color(hex: 0x7E5C8E), .clear],
                                            center: UnitPoint(x: 0.66, y: 0.62), startRadius: 0, endRadius: 58 * 0.37))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(KimaColor.hairline, lineWidth: 1))
                    .frame(width: 58, height: 58)
                if let initial = vm.currentUser?.username.first.map(String.init) {
                    Text(initial.lowercased())
                        .font(KimaType.figure)
                        .foregroundStyle(KimaColor.textPrimary)
                } else if vm.isLoadingUser {
                    ProgressView().tint(KimaColor.brand).scaleEffect(0.75)
                }
            }

            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                if let user = vm.currentUser {
                    Text(user.username)
                        .font(KimaType.headline)
                        .foregroundStyle(KimaColor.textPrimary)
                    if let role = user.role, !role.isEmpty {
                        Text(role.lowercased())
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textMuted)
                    }
                } else if !vm.isLoadingUser {
                    Text("couldn't load account")
                        .font(KimaType.body)
                        .foregroundStyle(KimaColor.textMuted)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(KimaSpacing.lg)
    }
}
