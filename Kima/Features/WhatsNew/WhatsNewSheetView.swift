import SwiftUI

// MARK: - What's-new window
// Opens on the maintainer's note with the changes listed beside it; a line opens that item's page. Closing answers
// no to every untouched choice and completes only once the server records it (else the window stays open and says
// so). One release at a time (WhatsNewGateModel). Links open only screens the app has (`/vibe`, `/stats…`).

/// Presentational state for the window's interactive items: the user's
/// explicit answers this session (reverted on POST failure, web parity), plus
/// run-from-window action status. Owned by WhatsNewSheetView.
struct WhatsNewItemState {
    var choices: [String: Bool] = [:]
    var runningKey: String?
    var startedKey: String?
    var runError: String?
}

struct WhatsNewSheetView: View {
    @Environment(AppEnvironment.self) private var env

    let release: WhatsNewRelease
    let onClose: () -> Void
    /// "Take me to it": dismiss server-side, navigate, and defer the rest.
    let onGoToTarget: (String) -> Void

    @State private var items = WhatsNewItemState()
    /// The item whose page is on screen; nil shows the note and the list.
    @State private var openedKey: String?
    @State private var isClosing = false
    @State private var closeError: String?
    @State private var showRunConfirm = false

    // MARK: - The web's grouping, same rule

    /// A decision is a choice, or an action that either runs here or says what closing means.
    private func isDecision(_ item: WhatsNewItem) -> Bool {
        item.kind == .choice || (item.kind == .action && (item.runsFromWindow || item.ifClosed != nil))
    }
    private var needsYou: [WhatsNewItem] { release.items.filter(isDecision) }
    private var whatChanged: [WhatsNewItem] { release.items.filter { !isDecision($0) } }
    private var opened: WhatsNewItem? { release.items.first { $0.key == openedKey } }

    /// An item still waiting on the user: a choice not answered, a decision action not taken.
    private var waiting: [WhatsNewItem] {
        release.items.filter { isDecision($0) && !settled($0) }
    }
    private func settled(_ item: WhatsNewItem) -> Bool {
        if item.kind == .choice { return items.choices[item.key] != nil }
        return items.startedKey == item.key
    }
    private var unansweredChoices: Int {
        release.items.filter { $0.kind == .choice && items.choices[$0.key] == nil }.count
    }

    /// The tag on a list line: what the user already answered or ran.
    private func tag(_ item: WhatsNewItem) -> String? {
        if item.kind == .choice, let answer = items.choices[item.key] { return answer ? "on" : "off" }
        if item.kind == .action, items.startedKey == item.key { return "done" }
        return nil
    }

    private var runAction: WhatsNewItem? {
        release.items.first { $0.kind == .action && $0.runsFromWindow }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            KimaHairline()
            // Two ScrollViews, not one with a swapped child: a fresh scroll view starts at the top,
            // which is what each view owes the reader when the content changes under them.
            Group {
                if let item = opened {
                    ScrollView { pageColumn { itemPage(item) } }
                } else {
                    ScrollView { pageColumn { overview } }
                }
            }
            KimaHairline()
            footer
        }
        .background(KimaColor.surfaceRaised)
        .presentationCornerRadius(28)
        .presentationBackground(KimaColor.surfaceRaised)
        .interactiveDismissDisabled(true)   // closing is a real answer — button only
        .confirmationDialog(
            runAction?.confirmTitle ?? "run this now?",
            isPresented: $showRunConfirm,
            titleVisibility: .visible
        ) {
            Button(runAction?.confirmLabel ?? "run it", role: .destructive) { runReembed() }
            Button("not now", role: .cancel) {}
        } message: {
            Text(runAction?.confirmMessage ?? "")
        }
    }

    private func pageColumn<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xl) {
            content()
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: KimaSpacing.md) {
            Text(release.title.lowercased())
                .font(KimaType.pageTitle)
                .foregroundStyle(KimaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("whatsnew-title")
            Spacer(minLength: KimaSpacing.md)
            if isClosing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: KimaLayout.chromeDiscSize, height: KimaLayout.chromeDiscSize)
            } else {
                KimaCloseButton(label: "close", id: "whatsnew-close", kind: .screen) { close() }
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.top, KimaSpacing.xl)
        .padding(.bottom, KimaSpacing.lg)
    }

    // MARK: - Overview: the note, then the list

    private var overview: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xxl) {
            if let note = release.note {
                noteBlock(note)
            }
            list
        }
    }

    private func noteBlock(_ note: WhatsNewNote) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            Text("a note from \(note.from)".lowercased())
                .font(KimaType.headline)
                .foregroundStyle(KimaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            WhatsNewItemBody(text: note.body)
            Text(note.from.lowercased())
                .font(KimaType.headline)
                .foregroundStyle(KimaColor.textPrimary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whatsnew-note")
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.lg) {
            Text("what's new in \(release.shortVersion)")
                .font(KimaType.headline)
                .foregroundStyle(KimaColor.textPrimary)
            group("needs you", needsYou)
            group("what changed", whatChanged)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whatsnew-list")
    }

    @ViewBuilder
    private func group(_ label: String, _ members: [WhatsNewItem]) -> some View {
        if !members.isEmpty {
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(label)
                    .font(KimaType.caption)
                    .tracking(1.2)
                    .foregroundStyle(KimaColor.textMuted)
                VStack(spacing: KimaSpacing.xs) {
                    ForEach(members) { row($0) }
                }
            }
        }
    }

    /// One line in the list: the item's title, its one-liner, and a chevron. Tapping opens its page.
    private func row(_ item: WhatsNewItem) -> some View {
        Button {
            openedKey = item.key
        } label: {
            HStack(alignment: .center, spacing: KimaSpacing.md) {
                VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.sm) {
                        Text(item.title.lowercasedFirstSentence())
                            .font(KimaType.headline)
                            .foregroundStyle(KimaColor.textPrimary)
                            .lineLimit(2)
                        Spacer(minLength: KimaSpacing.sm)
                        if let tag = tag(item) {
                            Text(tag)
                                .font(KimaType.caption)
                                .foregroundStyle(KimaColor.textMuted)
                        }
                    }
                    Text(item.summary.lowercased())
                        .font(KimaType.body)
                        .foregroundStyle(KimaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KimaColor.textMuted)
            }
            .padding(.vertical, KimaSpacing.md)
            .padding(.horizontal, KimaSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("whatsnew-row")
        .accessibilityIdentifier("whatsnew-row-\(item.key)")
    }

    // MARK: - An item's own page

    private func itemPage(_ item: WhatsNewItem) -> some View {
        WhatsNewItemPageView(
            item: item,
            backLabel: backLabel,
            state: $items,
            onBack: { openedKey = nil },
            onAnswer: answer,
            onRequestRun: { showRunConfirm = true },
            onGoToTarget: goToTarget
        )
    }

    /// "< kevin's note" when there is a note to go back to, "< what's new" when there isn't.
    private var backLabel: String {
        release.note.map { "\($0.from)'s note".lowercased() } ?? "what's new"
    }

    // MARK: - Footer

    private var footer: some View {
        WhatsNewFooterView(
            closeError: closeError,
            waitingLabel: waitingLabel,
            onWaiting: waiting.isEmpty ? nil : {
                // One thing waiting: show its page. Several: back to the list, where they all are.
                openedKey = waiting.count == 1 ? waiting[0].key : nil
            },
            buttonLabel: isClosing ? "saving…" : (unansweredChoices > 0 ? "close" : "done"),
            isClosing: isClosing,
            onClose: close
        )
    }

    /// "needs you: the new vibe engine" / "2 things need you" — the web's footer prompt.
    private var waitingLabel: String? {
        guard !waiting.isEmpty else { return nil }
        if waiting.count == 1 { return "needs you: \(waiting[0].title.lowercasedFirstSentence())" }
        return "\(waiting.count) things need you"
    }

    // MARK: - Actions (web-parity ordering)

    private func close() {
        guard !isClosing else { return }          // one in-flight dismiss
        #if DEBUG
        // Synthetic probe releases (-kima-whatsnew, versions 9.99.x) have no
        // server row, so the dismiss POST would 404 (server truth, correct for
        // real releases). The injection exists to sweep this UI on servers
        // without pending-release data — close locally, DEBUG-only.
        if release.version.hasPrefix("9.99.") { onClose(); return }
        #endif
        isClosing = true
        closeError = nil
        Task {
            do {
                try await env.client.postWhatsNewDismiss(version: release.version)
                onClose()
            } catch {
                isClosing = false
                closeError = "couldn't save. check your connection and tap done again."
            }
        }
    }

    private func answer(_ key: String, enabled: Bool) {
        items.choices[key] = enabled
        Task {
            do {
                try await env.client.postWhatsNewChoice(version: release.version, key: key, enabled: enabled)
            } catch {
                items.choices[key] = nil          // revert the button, web parity
            }
        }
    }

    private func goToTarget(_ path: String) {
        // The target lives on its permanent page; a dialogue is a bad place to
        // work through forty tracks. Defer the remaining windows, dismiss, then
        // navigate.
        env.whatsNew.deferRest()
        Task { try? await env.client.postWhatsNewDismiss(version: release.version) }
        onGoToTarget(path)
    }

    private func runReembed() {
        guard let key = runAction?.key, items.runningKey == nil else { return }
        items.runningKey = key
        items.runError = nil
        Task {
            do {
                try await env.client.resetVibeEmbeddings()
                items.runningKey = nil
                items.startedKey = key
            } catch {
                items.runningKey = nil
                items.runError = "couldn't start the rebuild. you can run it later in kima's web settings."
            }
        }
    }
}
