import SwiftUI

/// Quick "what happened?" report sheet, opened from the More tab. Context is snapshotted once on appear.
/// "open on github" saves a copy on the phone and opens GitHub's new-issue page, prefilled with exactly what the
/// "sent to github" card lists; the person signs in and submits there. "save on phone only" just saves the copy.
struct IssueReportSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss

    @State private var note = ""
    /// Context frozen at tap time (populated in `.onAppear`).
    @State private var snapshot: IssueReport?
    /// The prefilled GitHub page while it is open in the in-app browser.
    @State private var githubPage: URL?

    // Keyboard dismissal: the keyboard can always be put away.
    // Return only dismisses the keyboard — submission stays button-only.
    @FocusState private var noteFocused: Bool

    /// The snapshot with the typed note: what both buttons save and what the github card shows.
    private var report: IssueReport {
        var report = snapshot ?? captureContext()
        report.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return report
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KimaScreenGround()
                ScrollView {
                    VStack(alignment: .leading, spacing: KimaSpacing.lg) {
                        noteField
                        githubCard
                        actions
                        Spacer(minLength: KimaSpacing.huge)
                    }
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.top, KimaSpacing.lg)
                }
                .kimaKeyboardSafeCanvas()
            }
            .accessibilityIdentifier("issue-report-sheet")
            .navigationTitle("report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("cancel") { dismiss() }
                        .foregroundStyle(KimaColor.textMuted)
                }
            }
        }
        .kimaSafari(url: $githubPage) {
            toast.show("copy saved on phone", style: .success)
            dismiss()
        }
        .onAppear { if snapshot == nil { snapshot = captureContext() } }
        // A queue restored from the server can land after the sheet opens; re-capture so a
        // loaded (even paused) track is never reported as "nothing playing".
        .onChange(of: player.currentTrack?.id) { snapshot = captureContext() }
        .onChange(of: player.isActive) { snapshot = captureContext() }
    }

    // MARK: - Sections

    private var noteField: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            sectionLabel("what happened?")
            TextField("describe the problem", text: $note, axis: .vertical)
                .lineLimit(4...10)
                .kimaField()
                .focused($noteFocused)
                .submitLabel(.done)
                .onSubmit { noteFocused = false }
                .accessibilityLabel("what happened")
        }
    }

    /// Every field the GitHub page is prefilled with, nothing more.
    private var githubCard: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            sectionLabel("sent to github")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(GitHubIssueLink.fields(for: report).enumerated()), id: \.offset) { index, field in
                    if index > 0 { KimaHairline() }
                    fieldRow(field.label, field.value.isEmpty ? "—" : field.value)
                }
            }
            .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("issue-report-github-fields")
        }
    }

    private func fieldRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.md) {
            Text(label)
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.md)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(KimaType.captionStrong)
            .foregroundStyle(KimaColor.textSecondary)
            .tracking(0.1)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            Text("this opens github in your browser; you'll need a github account")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
            KimaPrimaryButton(title: "open on github", systemImage: "arrow.up.right") { openOnGitHub() }
            KimaPrimaryButton(title: "save on phone only", style: .secondary) { saveOnPhoneOnly() }
        }
        .padding(.top, KimaSpacing.xs)
    }

    // MARK: - Actions

    private func openOnGitHub() {
        guard githubPage == nil else { return }
        let report = report
        guard let page = GitHubIssueLink.url(for: report) else { return saveOnPhoneOnly() }
        env.issueReports.append(report)
        noteFocused = false
        githubPage = page
    }

    private func saveOnPhoneOnly() {
        env.issueReports.append(report)
        toast.show("report saved on phone", style: .success)
        dismiss()
    }

    // MARK: - Context capture

    /// Snapshot the surrounding context at tap time. Every field is best-effort; a report with
    /// only a timestamp is still valid.
    private func captureContext() -> IssueReport {
        let track = player.currentTrack
        let isLong = player.playbackType.isLongForm
        let hasItem = player.isActive
        let meta = player.longFormNowPlayingMeta

        let kind: String
        switch player.playbackType {
        case .track:          kind = track != nil ? "music" : "nothing playing"
        case .audiobook:      kind = "audiobook"
        case .podcastEpisode: kind = "podcast"
        }

        let title  = isLong ? meta?.title  : track?.effectiveTitle
        let artist = isLong ? meta?.artist : track?.artist?.name
        let info = Bundle.main.infoDictionary

        return IssueReport(
            note: "",
            screen: Self.screenName(env.router.selectedTab),
            playbackType: kind,
            nowPlayingTitle: title,
            nowPlayingArtist: artist,
            positionSeconds: hasItem ? player.currentTime : nil,
            durationSeconds: hasItem ? player.duration : nil,
            isPlaying: hasItem ? player.isPlaying : nil,
            appVersion: info?["CFBundleShortVersionString"] as? String,
            appBuild: info?["CFBundleVersion"] as? String,
            serverHost: env.server.baseURL.host(),
            systemVersion: DeviceInfo.system,
            deviceModel: DeviceInfo.model
        )
    }

    /// The selected tab as the screen name a report carries.
    private static func screenName(_ tab: AppTab) -> String {
        switch tab {
        case .home:       return "home"
        case .library:    return "library"
        case .audiobooks: return "audiobooks"
        case .podcasts:   return "podcasts"
        case .more:       return "more"
        }
    }
}
