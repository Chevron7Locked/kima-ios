import SwiftUI

// MARK: - Mood-mix choice

/// The mood-mix item inside the window: save as playlist, rebuild, keep — or,
/// for a mix under a removed mood, save / remove. Nothing clears until
/// Rebuild/Remove; the server's recorded answer is loaded first so an answer
/// given on another device shows here.
struct MoodMixChoiceView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var state: MoodMixReleaseState?
    @State private var loadFailed = false
    @State private var busy: String?          // "save" | "rebuild" | "keep" | "remove"
    @State private var error: String?
    /// The mix is gone once cleared, so remember which wording cleared it.
    @State private var removedRetired = false

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            if loadFailed {
                Text("couldn't load your mood mix. it hasn't been changed.")
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.danger)
            } else if let state {
                content(state)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        // No .accessibilityIdentifier on this container: SwiftUI passes a container's
        // identifier down to its buttons and hides their own ids (XCUITest would see
        // every button as 'moodmix').
        .task {
            do {
                let s = try await env.client.getMoodMixState()
                guard !loadFailed else { return }
                state = s
            } catch {
                loadFailed = true
            }
        }
    }

    @ViewBuilder
    private func content(_ state: MoodMixReleaseState) -> some View {
        if let mix = state.mix {
            Text("\(mix.name.lowercasedFirstSentence()) · \(mix.trackCount) \(mix.trackCount == 1 ? "track" : "tracks")")
                .font(KimaType.body)
                .foregroundStyle(KimaColor.textPrimary)
            if let playlist = state.playlist {
                savedNote(playlist)
            } else {
                saveButton()
            }
            HStack(spacing: KimaSpacing.sm) {
                if mix.retired {
                    // Can't be shown any more, so there is nothing to keep.
                    decisionButton("remove", action: "remove", selected: false, testId: "moodmix-remove")
                } else {
                    decisionButton("rebuild", action: "rebuild", selected: false, testId: "moodmix-rebuild")
                    decisionButton("keep", action: "keep", selected: state.decision == "keep", testId: "moodmix-keep")
                }
            }
        } else {
            // Cleared: the mix is gone. Only a playlist saved before remains.
            if let playlist = state.playlist {
                savedNote(playlist)
            }
            Label(clearedCopy(state.decision), systemImage: "checkmark.circle")
                .font(KimaType.body)
                .foregroundStyle(KimaColor.positive)
        }
        if let error {
            Text(error).font(KimaType.body).foregroundStyle(KimaColor.danger)
        }
    }

    private func clearedCopy(_ decision: String?) -> String {
        if decision != "rebuild" { return "you don't have a saved mood mix." }
        return removedRetired ? "removed." : "cleared. pick a mood in the mood mixer to make a new one."
    }

    @ViewBuilder
    private func savedNote(_ playlist: MoodMixReleaseState.Ref?) -> some View {
        if let playlist {
            Label("saved as the playlist \(playlist.name.lowercasedFirstSentence())",
                  systemImage: "checkmark.circle")
                .font(KimaType.body)
                .foregroundStyle(KimaColor.positive)
                .accessibilityIdentifier("moodmix-saved")
        }
    }

    private func saveButton() -> some View {
        Button {
            save()
        } label: {
            HStack(spacing: KimaSpacing.xs) {
                if busy == "save" { ProgressView().controlSize(.small) }
                Text(busy == "save" ? "saving…" : "save as playlist")
            }
        }
        .buttonStyle(WhatsNewQuietButtonStyle())
        .disabled(busy != nil)
        .accessibilityIdentifier("moodmix-save")
    }

    private func decisionButton(_ label: String, action: String, selected: Bool, testId: String) -> some View {
        Button {
            decide(action)
        } label: {
            HStack(spacing: KimaSpacing.xs) {
                if busy == action {
                    ProgressView().controlSize(.small)
                } else if selected {
                    Image(systemName: "checkmark")
                }
                Text(label)
            }
        }
        .buttonStyle(WhatsNewQuietButtonStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .disabled(busy != nil)
        .accessibilityIdentifier(testId)
    }

    // MARK: Actions (web ordering: call, then reflect server truth locally)

    private func save() {
        guard busy == nil, let mix = state?.mix else { return }
        busy = "save"
        error = nil
        Task {
            do {
                let saved = try await env.client.saveMoodMixAsPlaylist(mixId: mix.id)
                state?.playlist = .init(id: saved.id, name: saved.name)
            } catch {
                self.error = "couldn't save it as a playlist. your mix is untouched."
            }
            busy = nil
        }
    }

    private func decide(_ action: String) {
        guard busy == nil else { return }
        busy = action
        error = nil
        Task {
            do {
                try await env.client.decideMoodMixes(action)
                if action == "remove" { removedRetired = true }
                // rebuild/remove clear the mix server-side; keep leaves it.
                state?.decision = (action == "keep") ? "keep" : "rebuild"
                if action != "keep" { state?.mix = nil }
                // Rebuild/removal clears the device's saved-mix UI — nudge the
                // home mood mixer to refetch (it re-reads on appear).
                NotificationCenter.default.post(name: .kimaMoodMixCleared, object: nil)
            } catch {
                self.error = (action == "keep")
                    ? "couldn't save your answer."
                    : "couldn't clear your mix. it's still there."
            }
            busy = nil
        }
    }
}
