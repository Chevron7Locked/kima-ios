import SwiftUI

// MARK: - PrivacyPolicyView

/// The app's own privacy policy, shipped in the binary: the iOS client collects nothing, so
/// this describes the app's real network + storage behavior rather than a legal template.
/// The Kima *server* policy is a separate document, linked below and gated so a placeholder
/// URL can never render as a broken row.
struct PrivacyPolicyView: View {
    /// The server's privacy policy. nil until the URL is real —
    /// the row only renders when it resolves (REPLACE-ME guard).
    private var serverPolicyURL: URL? {
        let s = "https://github.com/Chevron7Locked/kima-hub/blob/main/PRIVACY.md"
        return s.contains("REPLACE-ME") ? nil : URL(string: s)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                KimaScreenHeader(title: "privacy policy")
                block("summary") {
                    Text("kima only talks to your own server. nothing that identifies you is sent to the developer: no backend, no analytics, no tracking, no ads. delete the app and nothing of yours is left with us.")
                }

                block("stored on this device") {
                    bullet("your server address and sign-in token, kept in the iOS keychain on this device only. they are never synced and are sent only to your server")
                    bullet("app preferences (playback speed, sort order, display settings), stored on this device")
                    bullet("plays recorded while offline, kept until they're sent to your server (track ids and times only, never passwords)")
                    bullet("cover art is cached in memory only. nothing that needs your sign-in is saved to disk")
                    bullet("problem reports you file (your note, the screen, what was playing, the app and iOS versions, the device model, and your server address), kept until you clear them in settings › issue reports")
                }

                block("what your server stores") {
                    Text("your play history, stats, playlists, and library info are stored on your server, on hardware you choose. the app reads and changes that data but doesn't copy it anywhere else. to delete it, delete it on your server.")
                    if let url = serverPolicyURL {
                        Link("server privacy policy",
                             destination: url)
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textPrimary)
                            .padding(.top, KimaSpacing.sm)
                    }
                }

                block("what the app connects to") {
                    bullet("your server: every request. the app checks the address of every request and attaches your sign-in only when it's your server, so it never goes to image sites")
                    bullet("cover art sites (iTunes, Deezer, and similar): images only, fetched directly and anonymously, with no cookies and no sign-in")
                    bullet("Apple: keychain, background audio, lock screen controls. Apple's terms apply")
                    bullet("GitHub: only when you tap \"open on github\" on a problem report. it opens GitHub's new-issue page with your note, the app and iOS versions, the device model, and the screen. nothing is filed until you submit it there, from your own GitHub account")
                    Text("no analytics, crash reporting, ad tracking, or telemetry of any kind. every request the app makes is in its network source files.")
                }

                block("changes") {
                    Text("if this policy changes, the app's about screen and the changelog will say so, with the date.")
                }

                block("source code") {
                    Text("the app's source code is public, so you can check all of this yourself.")
                }

                Spacer(minLength: KimaSpacing.lg)
            }
        }
        .kimaScrollTopGround()
        .kimaMiniPlayerClearance()
        .kimaScreenCanvas()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func block(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            KimaSectionHeader(title: title)
            VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                content()
            }
            .font(KimaType.body)
            .foregroundStyle(KimaColor.textPrimary)
            .padding(KimaSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card))
            .padding(.horizontal, KimaSpacing.xl)
        }
        .padding(.bottom, KimaSpacing.lg)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: KimaSpacing.sm) {
            Text("·")
                .foregroundStyle(KimaColor.textMuted)
            Text(text)
        }
    }
}
