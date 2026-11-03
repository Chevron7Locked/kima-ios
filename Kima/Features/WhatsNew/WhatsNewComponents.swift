import SwiftUI

// MARK: - What's-new shared pieces
//
// Button styles, the mood-mix choice view, and display helpers for the release window.
// Button chrome matches the web (h-11, rounded-lg).

// MARK: - Button styles (web h-11 px-4 rounded-lg chrome)

/// Brand-filled confirm ("turn it on", "done", "run it").
struct WhatsNewFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(KimaType.headline)
            .foregroundStyle(KimaColor.onBrand)
            .padding(.horizontal, KimaSpacing.lg)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: KimaRadius.card)
                    .fill(KimaColor.brand)
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .contentShape(Rectangle())
    }
}

/// Tonal secondary ("save as playlist", "no thanks", "take me to it"). A selected option reads like
/// a selected segment: amber text on a faint amber tint.
struct WhatsNewQuietButtonStyle: ButtonStyle {
    var selected: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(KimaType.headline)
            .foregroundStyle(selected ? KimaColor.brand : KimaColor.textSecondary)
            .padding(.horizontal, KimaSpacing.lg)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: KimaRadius.card)
                    .fill(selected ? KimaColor.brandTint
                         : configuration.isPressed ? KimaColor.surfaceActive
                         : KimaColor.surfaceHover)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Footer (web WhatsNewWindow footer: the "what closing means" line + Done)

struct WhatsNewFooterView: View {
    let closeError: String?
    /// "needs you: <item>" / "2 things need you" — tappable, takes the reader to what is waiting.
    let waitingLabel: String?
    let onWaiting: (() -> Void)?
    let buttonLabel: String
    let isClosing: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: KimaSpacing.md) {
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                if let closeError {
                    Text(closeError)
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.danger)
                        .accessibilityIdentifier("whatsnew-close-error")
                } else if let waitingLabel, let onWaiting {
                    Button(action: onWaiting) {
                        Text(waitingLabel)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textPrimary)
                    .accessibilityIdentifier("whatsnew-waiting")
                    Text("anything you don't answer stays as it is.")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("tap done to close.")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                }
            }
            Spacer(minLength: KimaSpacing.md)
            Button(buttonLabel, action: onClose)
                .buttonStyle(WhatsNewFilledButtonStyle())
                .disabled(isClosing)
                .accessibilityIdentifier("whatsnew-done")
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.lg)
    }
}

extension Notification.Name {
    /// Posted when a mood-mix decision clears the saved mix, so the home Mood
    /// Mixer refreshes its own view of it (web parity: the web component
    /// remounts; iOS has no remount on a background tab).
    static let kimaMoodMixCleared = Notification.Name("kima.moodMixCleared")
}

// MARK: - Display helpers

extension String {
    /// Blank-line-separated server copy rendered as real paragraphs.
    var paragraphs: [String] {
        components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The lowercase sweep applies to our copy; the server writes title-case
    /// prose. Sentence-case at display: first letter of the whole string goes
    /// lowercase (proper nouns inside the sentence keep their case — the web
    /// renders the same strings verbatim in its lowercase window).
    func lowercasedFirstSentence() -> String {
        guard let first = self.first, first.isUppercase else { return self }
        return first.lowercased() + self.dropFirst()
    }
}

#if DEBUG
extension WhatsNewRelease {
    /// Synthetic release for the `-kima-whatsnew <n>` launch probe (same spirit
    /// as -kima-vibe-computing): exercises the whole window UI — note, action
    /// with confirm, choice — on a fresh install with no seeded release rows.
    /// Server answers override it in WhatsNewGateModel.
    static func debugSample(n: Int) -> [WhatsNewRelease] {
        var out: [WhatsNewRelease] = []
        // n == 3 is a single-window probe (mood-mix panel alone): it must not accumulate A/B.
        // It renders the real MoodMixChoiceView against the connected server's mood-mix state
        // (with no mix it shows the cleared-state copy).
        // n == 4: the play-count cleanup item, whose link opens Stats at the false-starts section.
        if n == 4 {
            return [WhatsNewRelease(
                version: "9.99.4",
                title: "Probe release D — cleanup link",
                summary: "Opens Stats at the false-starts section.",
                date: "2026-01-04",
                note: nil,
                items: [
                    WhatsNewItem(kind: .action, key: "plays.repair",
                                 title: "Clean up old play counts",
                                 summary: "Find the skips that were counted as plays, and remove them.",
                                 body: "A tool on the Stats page finds plays that were really skips.",
                                 cta: nil, run: nil,
                                 confirmTitle: nil, confirmMessage: nil,
                                 confirmLabel: nil, ifClosed: nil, discloses: nil,
                                 links: [WhatsNewLink(label: "Open the cleanup", href: "/stats#false-starts")]),
                ])]
        }
        if n == 3 {
            return [WhatsNewRelease(
                version: "9.99.3",
                title: "Probe release C — mood mix",
                summary: "Renders the live mood-mix choice panel against the server's state.",
                date: "2026-01-03",
                note: nil,
                items: [
                    WhatsNewItem(kind: .action, key: "moods.mixes.retired",
                                 title: "Your old mood mix can't be shown any more",
                                 summary: "Its mood no longer exists. Save it as a playlist or remove it.",
                                 body: "Save it as a playlist to keep those tracks together, or remove it.",
                                 cta: "Save as playlist", run: nil,
                                 confirmTitle: nil, confirmMessage: nil,
                                 confirmLabel: nil,
                                 ifClosed: "If you close now, nothing is deleted, and you'll be asked again next time.",
                                 discloses: nil),
                ])]
        }
        // n == 5: the run-from-window action, the shape the server sends as
        // `run:"wipeEnrichment"` — confirm dialog, the started state, and the
        // "needs you" footer prompt. The confirm is cancelled, never run: the
        // real POST would wipe a live library's enrichment.
        if n == 5 {
            return [WhatsNewRelease(
                version: "9.99.5",
                title: "Probe release E — wipe",
                summary: "The run-from-window action and what closing without acting means.",
                date: "2026-01-05",
                note: WhatsNewNote(from: "Kevin", body: "This one asks you to run the engine again."),
                items: [
                    WhatsNewItem(kind: .action, key: "engine.wipe",
                                 title: "Wipe and re-run enrichment",
                                 summary: "The engine is new, so it needs one fresh run.",
                                 body: "Wiping clears what Kima worked out about your music and runs it through the new engine.",
                                 cta: "Wipe and re-run", run: "wipeEnrichment",
                                 confirmTitle: "Wipe and re-run enrichment?",
                                 confirmMessage: "Your music, playlists, plays, likes and edits stay.",
                                 confirmLabel: "Wipe and re-run",
                                 ifClosed: "If you close now, nothing is wiped.",
                                 discloses: nil,
                                 links: [WhatsNewLink(label: "Open the vibe map", href: "/vibe")]),
                ])]
        }
        if n >= 1 {
            out.append(WhatsNewRelease(
                version: "9.99.1",
                title: "Probe release A",
                summary: "Synthetic window for the launch probe — dismiss posts to the server for real.",
                date: "2026-01-01",
                // The window opens on this note with the items below it as a list, so the probe
                // sweeps the overview, an item's own page, and the way back.
                note: WhatsNewNote(from: "Kevin",
                                   body: "Hey y'all.\n\nThis probe checks the note, the list and the pages."),
                items: [
                    WhatsNewItem(kind: .note, key: "probe.note", title: "A note",
                                 summary: "Two paragraphs, rendered as two.",
                                 body: "First paragraph.\n\nSecond paragraph, rendered as two.",
                                 cta: nil, run: nil,
                                 confirmTitle: nil, confirmMessage: nil, confirmLabel: nil,
                                 ifClosed: nil, discloses: nil),
                    WhatsNewItem(kind: .choice, key: "probe.choice", title: "Turn on the probe?",
                                 summary: "A default of off; dismissing records the default.",
                                 body: "A choice defaults to off; dismissing records the default.",
                                 cta: nil, run: nil,
                                 confirmTitle: nil, confirmMessage: nil, confirmLabel: nil,
                                 ifClosed: nil,
                                 discloses: "Nothing leaves the device."),
                ]))
        }
        if n >= 2 {
            out.append(WhatsNewRelease(
                version: "9.99.2",
                title: "Probe release B",
                summary: "Second window — the queue must show A first (oldest first).",
                date: "2026-01-02",
                note: nil,
                items: [
                    WhatsNewItem(kind: .note, key: "probe.note2", title: "Order check",
                                 summary: "If you see this before A, the queue order is wrong.",
                                 body: "If you see this before A, the queue order is wrong.",
                                 cta: nil, run: nil,
                                 confirmTitle: nil, confirmMessage: nil, confirmLabel: nil,
                                 ifClosed: nil, discloses: nil),
                ]))
        }
        return out
    }
}
#endif
