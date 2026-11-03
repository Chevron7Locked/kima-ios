import SwiftUI

// MARK: - About

struct SettingsAboutSection: View {
    @Environment(AppEnvironment.self) private var env
    @State private var update: ServerUpdateStatus?
    @State private var openCount = 0

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "kima \(v) (\(b))"
    }

    var body: some View {
        KimaSectionHeader(title: "about")

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("version")
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textPrimary)
                Spacer(minLength: 0)
                Text(versionString)
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
            }
            .padding(.vertical, KimaSpacing.lg)

            if let update {
                KimaHairline()
                serverVersionRow(update)
            }

            KimaHairline()

            SettingsNavRow(destination: { ChangelogView() }) {
                HStack(spacing: KimaSpacing.sm) {
                    Text("changelog")
                    Spacer(minLength: 0)
                    if openCount > 0 {
                        Text("\(openCount) open")
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textSecondary)
                    }
                }
            }

            KimaHairline()

            SettingsNavRow(destination: { LicensesView() }) { Text("licenses") }

            KimaHairline()

            SettingsNavRow(destination: { PrivacyPolicyView() }) { Text("privacy policy") }

            KimaHairline()

            Link(destination: URL(string: "mailto:feedback@chevron7.io?subject=Kima%20iOS%20Feedback")!) {
                HStack {
                    Text("email feedback")
                        .font(KimaType.body)
                        .foregroundStyle(KimaColor.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "envelope")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(KimaColor.textMuted)
                }
                .padding(.vertical, KimaSpacing.lg)
                .contentShape(Rectangle())
            }

            KimaHairline()

            // Local issue log — the reports filed from the More tab.
            SettingsNavRow(destination: { IssueReportsView() }) { Text("issue reports") }
        }
        .padding(.horizontal, KimaSpacing.lg)
        // Re-read on every appearance: an open item can settle on the server between visits.
        .task {
            async let status = try? env.client.getServerUpdateStatus()
            async let open = try? env.client.getOpenRequirementCount()
            // A failed check keeps what the rows already show.
            if let status = await status { update = status }
            if let open = await open { openCount = open }
        }
    }

    /// The server's version; with a newer release out, a small amber dot and a second line naming it.
    private func serverVersionRow(_ status: ServerUpdateStatus) -> some View {
        HStack(alignment: .center, spacing: KimaSpacing.sm) {
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text("server")
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textPrimary)
                if status.hasUpdate, let latest = status.latest {
                    Text("update available · v\(latest)")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                }
            }
            Spacer(minLength: 0)
            if status.hasUpdate {
                Circle()
                    .fill(KimaColor.brand)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text("v\(status.current)")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
        }
        .padding(.vertical, KimaSpacing.lg)
        .accessibilityElement(children: .combine)
    }
}

/// A settings row: a label with a chevron that pushes `destination`.
struct SettingsNavRow<Label: View, Destination: View>: View {
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let label: () -> Label

    var body: some View {
        NavigationLink(destination: destination()) {
            HStack {
                label()
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KimaColor.textMuted)
            }
            .padding(.vertical, KimaSpacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
