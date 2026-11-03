import SwiftUI

// MARK: - An item's own page
// How one item's page looks and what its controls do; WhatsNewSheetView owns the window and every server call.
// The answer arrives as a binding from the sheet, so this page, the list line's tag and the footer's
// "needs you" line always agree.

/// One item's body copy. Server copy carries blank lines between paragraphs, so render them as the
/// paragraphs they are, each with its first sentence lowercased to match the app's voice.
struct WhatsNewItemBody: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            ForEach(Array(text.paragraphs.enumerated()), id: \.offset) { _, para in
                Text(para.lowercasedFirstSentence())
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// An item's page: back link, title, body, the controls its kind asks for, and the links iOS can
/// actually open. The sheet swaps this in over the list; the back link hands control back.
struct WhatsNewItemPageView: View {
    let item: WhatsNewItem
    /// "< kevin's note" when there is a note to go back to, "< what's new" when there isn't.
    let backLabel: String
    /// The window's shared item state — answers, run status. Owned by WhatsNewSheetView.
    @Binding var state: WhatsNewItemState
    let onBack: () -> Void
    let onAnswer: (String, Bool) -> Void
    /// Ask the sheet to raise its confirm dialog. The dialog belongs to the window, not the page.
    let onRequestRun: () -> Void
    let onGoToTarget: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.lg) {
            backButton

            Text(item.title.lowercasedFirstSentence())
                .font(KimaType.pageTitle)
                .foregroundStyle(KimaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("whatsnew-item-title")

            WhatsNewItemBody(text: item.body)

            if item.kind == .choice {
                choiceControls
            } else if item.kind == .action {
                actionControls
            }

            captions
            linkButtons
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whatsnew-page")
    }

    private var backButton: some View {
        Button {
            onBack()
        } label: {
            HStack(spacing: KimaSpacing.xs) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text(backLabel)
            }
            .font(KimaType.body)
            .foregroundStyle(KimaColor.textSecondary)
            .padding(.vertical, KimaSpacing.sm)
            .padding(.leading, KimaSpacing.xs)
            .padding(.trailing, KimaSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("whatsnew-back")
    }

    // MARK: - Choice

    private var choiceControls: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            if let discloses = item.discloses {
                (Text("what leaves your server: ")
                    .foregroundStyle(KimaColor.textPrimary.opacity(0.7))
                 + Text(discloses.lowercased()).foregroundStyle(KimaColor.textMuted))
                    .font(KimaType.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: KimaSpacing.sm) {
                answerButton(label: "turn it on", enabled: true)
                answerButton(label: "no thanks", enabled: false)
            }
        }
        .padding(KimaSpacing.lg)
        .background(RoundedRectangle(cornerRadius: 14).fill(KimaColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(KimaColor.hairline))
    }

    @ViewBuilder
    private func answerButton(label: String, enabled: Bool) -> some View {
        let selected = state.choices[item.key] == enabled
        // Two branches, not a ternary over two ButtonStyles: `.buttonStyle` is type-fixed.
        if selected {
            Button { onAnswer(item.key, enabled) } label: {
                HStack(spacing: KimaSpacing.xs) { Image(systemName: "checkmark"); Text(label) }
            }
            .buttonStyle(WhatsNewFilledButtonStyle())
            .accessibilityLabel(label)
        } else {
            Button { onAnswer(item.key, enabled) } label: {
                Text(label)
            }
            .buttonStyle(WhatsNewQuietButtonStyle())
            .accessibilityLabel(label)
        }
    }

    // MARK: - Action

    private var actionControls: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            if item.key == "moods.mixes" || item.key == "moods.mixes.retired" {
                MoodMixChoiceView()
            } else if item.runsFromWindow {
                runFromWindowControl
            }
        }
    }

    /// The run-from-window action (1.11 "wipe and re-run enrichment"): confirm in the sheet,
    /// then POST /analysis/vibe/start {force:true} — the same call the web's Settings re-run makes.
    private var runFromWindowControl: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            if state.startedKey == item.key {
                Label("rebuild started. it runs in the background.",
                      systemImage: "checkmark.circle")
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.positive)
            } else if state.runError != nil, state.runningKey == nil {
                Text(state.runError ?? "")
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.danger)
            } else {
                Button {
                    onRequestRun()
                } label: {
                    HStack(spacing: KimaSpacing.sm) {
                        if state.runningKey == item.key { ProgressView().controlSize(.small) }
                        Text(state.runningKey == item.key
                             ? "starting…"
                             : (item.confirmLabel ?? item.cta ?? "run it").lowercased())
                    }
                }
                .buttonStyle(WhatsNewFilledButtonStyle())
                .disabled(state.runningKey != nil)
            }
            Text("or do it later in kima's web settings.")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
        }
    }

    // MARK: - Fine print

    /// What the server says happens if the user never answers, and what closing means for an
    /// action that hasn't been taken. Both are the server's words, lowercased like everything else.
    @ViewBuilder
    private var captions: some View {
        if item.kind == .choice, state.choices[item.key] == nil {
            Text("if you don't answer, it stays off.")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        if item.kind == .action, let ifClosed = item.ifClosed, state.startedKey != item.key {
            Text(ifClosed.lowercased())
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The links the app can actually open. Anything else is left to the item's own copy, which
    /// names where it lives — an iPhone has no page for the server's settings.
    @ViewBuilder
    private var linkButtons: some View {
        let routable = item.links.filter { $0.href.hasPrefix("/vibe") || $0.href.hasPrefix("/stats") }
        if !routable.isEmpty {
            VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                ForEach(routable, id: \.href) { link in
                    Button {
                        onGoToTarget(link.href)
                    } label: {
                        HStack(spacing: KimaSpacing.sm) {
                            Text(link.label.lowercased())
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .buttonStyle(WhatsNewQuietButtonStyle())
                    .accessibilityIdentifier("whatsnew-link")
                }
            }
        }
    }
}
