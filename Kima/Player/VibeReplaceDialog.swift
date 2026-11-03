import SwiftUI

/// The question shown when a new vibe queue would replace one that is playing.
struct VibeReplacePrompt: Equatable {
    let current: QueueOrigin
    let new: QueueOrigin

    /// One plain sentence, e.g. "replace the song path with similar tracks?"
    var question: String {
        "replace \(current.playingPhrase) with \(current == new ? new.anotherPhrase : new.newQueuePhrase)?"
    }
}

extension View {
    /// The replace question for a pending vibe queue. Each screen that can start a vibe queue hosts one;
    /// only the host that came on screen last shows it. `suppressed` holds a host back while a cover is
    /// opening over it.
    func vibeReplaceDialog(player: PlaybackController, suppressed: Bool = false) -> some View {
        modifier(VibeReplaceHost(player: player, suppressed: suppressed))
    }
}

/// One place the replace question can show. Hosts register on appear, so the screen on top asks.
private struct VibeReplaceHost: ViewModifier {
    let player: PlaybackController
    let suppressed: Bool
    @State private var id = UUID()

    private var shown: VibeReplacePrompt? {
        player.vibeReplaceHosts.last == id && !suppressed ? player.vibeReplacePrompt : nil
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if let prompt = shown {
                    VibeReplacePromptView(question: prompt.question) { player.resolveVibeReplace($0) }
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: shown)
            .onAppear { player.addVibeReplaceHost(id) }
            .onDisappear { player.removeVibeReplaceHost(id) }
    }
}

/// Kima's own replace question: the sentence and "keep" / "replace" on glass near the bottom, over a
/// dimmed screen. Tapping the dim, or the escape gesture, keeps the queue.
struct VibeReplacePromptView: View {
    let question: String
    let answer: (Bool) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
        ZStack(alignment: .bottom) {
            KimaColor.base.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { answer(false) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KimaSpacing.lg) {
                Text(question)
                    .font(KimaType.headline)
                    .foregroundStyle(KimaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("vibe-replace-question")
                HStack(spacing: KimaSpacing.md) {
                    KimaPrimaryButton(title: "keep", style: .secondary) { answer(false) }
                    KimaPrimaryButton(title: "replace") { answer(true) }
                }
            }
            .padding(KimaSpacing.xl)
            .background { shape.fill(Color.clear).kimaGlassChrome(in: shape).allowsHitTesting(false) }
            .overlay(shape.strokeBorder(KimaColor.hairline, lineWidth: 1))
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.bottom, KimaSpacing.lg)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { answer(false) }
        }
        .onAppear {
            // The keyboard would cover the buttons; the question needs the whole answer in view.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }
}

#if DEBUG
extension View {
    /// UI-test marker for the `-kima-vibe-fake-replace…` hooks: which kind of vibe queue is playing
    /// (`id`) and whether the replace question is open (`id`-asking).
    func debugVibeReplaceMarker(player: PlaybackController, id: String) -> some View {
        overlay(alignment: .topLeading) {
            if CommandLine.arguments.contains(where: { $0.hasPrefix("-kima-vibe-fake-replace") }) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.queueOrigin?.name ?? "none").accessibilityIdentifier(id)
                    Text(player.vibeReplacePrompt == nil ? "idle" : "asking").accessibilityIdentifier("\(id)-asking")
                }
                .font(KimaType.meta)
                .foregroundStyle(KimaColor.textMuted)
                .padding(.leading, KimaSpacing.xs)
            }
        }
    }
}
#endif
