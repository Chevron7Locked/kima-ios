import SwiftUI

// MARK: - Scrobbling
// Per-user ListenBrainz mirroring with the user's own token. The token is write-only: saved on its own POST
// (null clears), never read back; the saved state comes from hasListenbrainzToken. The live sharing switch
// appears only when the server says this user's listening is what the public vibe map shares (liveSharingAvailable).

struct ScrobblingSection: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    @State private var settings: UserSettings?
    @State private var token = ""
    @State private var clearRequested = false
    @State private var saving = false
    @State private var togglingShare = false

    private var configured: Bool { settings?.hasListenbrainzToken ?? false }
    private var dirty: Bool {
        (token.trimmingCharacters(in: .whitespaces).count > 0 && !clearRequested)
            || (clearRequested && configured)
    }

    var body: some View {
        // Render the shell from the first frame (a placeholder until /settings lands). A `Group` with an
        // `if let` has zero height while nil, and a zero-height row in a lazy List is never revealed, so its
        // `.task` never fires and the section never loads.
        section(settings ?? UserSettings())
            .task {
                guard settings == nil else { return }
                settings = (try? await env.client.getUserSettings()) ?? UserSettings()
            }
    }

    private func section(_ s: UserSettings) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header spans the full width (it owns its gutter); everything below sits on the gutter.
            KimaSectionHeader(title: "scrobbling")
            Text("send your plays to ListenBrainz.")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
                .padding(.horizontal, KimaSpacing.lg)

            // Hairline-separated rows on the gutter, like every other settings section.
            VStack(alignment: .leading, spacing: 0) {
                // The switch exists only on a server that shares this user's
                // listening publicly (web parity: omitted, not disabled).
                if s.liveSharingAvailable {
                    SettingsToggleRow(
                        label: "share live listening",
                        caption: "shows what you're playing on the public vibe map.",
                        isOn: Binding(
                            get: { s.shareLiveListening },
                            set: { share in setShare(share) }
                        )
                    )
                    .disabled(togglingShare)
                    KimaHairline()
                }

                VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                    Text("ListenBrainz token")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                    SecureField(
                        configured ? "token saved. paste a new one to replace it" : "paste your ListenBrainz token",
                        text: $token
                    )
                    .textFieldStyle(.plain)
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textPrimary)
                    .accessibilityIdentifier("scrobbling-token")
                    .padding(KimaSpacing.md)
                    .background(KimaColor.surfaceRaised, in: RoundedRectangle(cornerRadius: KimaRadius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: KimaRadius.card)
                            .strokeBorder(KimaColor.hairline, lineWidth: 1)
                    )
                    Text("create one at listenbrainz.org → settings → reset token")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textFaint)
                }
                .padding(.vertical, KimaSpacing.lg)

                if configured {
                    KimaHairline()
                    SettingsToggleRow(
                        label: "remove token",
                        caption: "stop sending plays to ListenBrainz",
                        isOn: $clearRequested
                    )
                }

                KimaHairline()

                HStack(spacing: KimaSpacing.md) {
                    Button {
                        save()
                    } label: {
                        Text(saving ? "saving…" : (clearRequested ? "remove token" : "save"))
                            .font(KimaType.headline)
                            .foregroundStyle(KimaColor.textPrimary)
                            .padding(.horizontal, KimaSpacing.lg)
                            .padding(.vertical, KimaSpacing.md)
                            .background(KimaColor.surfaceRaised, in: RoundedRectangle(cornerRadius: KimaRadius.card))
                    }
                    .buttonStyle(.plain)
                    .disabled(!dirty || saving)
                    .accessibilityIdentifier("scrobbling-save")
                    Spacer()
                }
                .padding(.vertical, KimaSpacing.lg)
            }
            .padding(.horizontal, KimaSpacing.lg)
        }
    }

    private func save() {
        saving = true
        let clear = clearRequested
        let value = token.trimmingCharacters(in: .whitespaces)
        Task {
            defer { saving = false }
            let patch = UserSettingsPatch(listenbrainzToken: clear ? .some(nil) : .some(value))
            guard let updated = try? await env.client.updateUserSettings(patch) else {
                toast.show("couldn't save. try again.", style: .error)
                return
            }
            settings = updated
            token = ""
            clearRequested = false
            toast.show(clear ? "token removed" : "scrobbling on", style: .success)
        }
    }

    private func setShare(_ share: Bool) {
        togglingShare = true
        Task {
            defer { togglingShare = false }
            guard let updated = try? await env.client.updateUserSettings(
                UserSettingsPatch(shareLiveListening: share)) else {
                toast.show("couldn't save. try again.", style: .error)
                return
            }
            settings = updated
        }
    }
}
