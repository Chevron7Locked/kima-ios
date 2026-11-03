import SwiftUI

// MARK: - SleepTimerModel

/// When the sleep timer should fire, beyond the minute countdown.
/// `.endOfChapter` means one audiobook FILE (Kima's chapter schema is one file per
/// chapter). `.endOfTrack` matches "End of Track" everywhere else in audio apps —
/// the current song, not the whole queue.
enum SleepTimerEndPolicy: Equatable, Sendable {
    case timed           // countdown only (legacy default)
    case endOfTrack      // pause when the current song ends
    case endOfEpisode    // pause when the current podcast episode ends
    case endOfChapter    // pause when the current audiobook chapter/file ends

    /// The end-of-item policy that fits what is playing: song, episode or chapter.
    static func endOfItem(for playback: LongFormPlaybackType) -> SleepTimerEndPolicy {
        switch playback {
        case .track:          return .endOfTrack
        case .podcastEpisode: return .endOfEpisode
        case .audiobook:      return .endOfChapter
        }
    }
}

/// Observable sleep-timer state, owned by `PlaybackController` so the countdown survives player
/// dismiss and reopen. Presets and custom minutes follow the web SleepTimer; the end-of-item
/// policies (track/episode/chapter) are evaluated on natural ends in PlaybackController+SleepPolicy.
@MainActor
@Observable
final class SleepTimerModel {

    // MARK: - State

    private(set) var remainingSeconds: Int? = nil
    private var countdownTask: Task<Void, Never>?

    /// End-of-item policy armed from the sheet. `.timed` means none. Evaluation and
    /// clearing live in PlaybackController+SleepPolicy.swift.
    var endPolicy: SleepTimerEndPolicy = .timed

    /// Programmatic sheet presentation (deep link kima://sleep-timer). The trigger
    /// button's own tap keeps a private @State path; any arm/cancel closes BOTH paths
    /// (see closeSheets).
    var showSheet = false

    /// Fires on the MainActor when the countdown reaches zero.
    /// Annotated @MainActor so the compiler enforces that the closure can safely call
    /// main-actor-isolated methods (e.g. player.pause()).
    var onExpiry: (@MainActor () -> Void)?

    /// What is playing now, so the sheet offers only the end-of-item row that fits it. Assigned by
    /// the owning `PlaybackController`; nil shows every row.
    var currentPlayback: (@MainActor () -> LongFormPlaybackType)?

    // MARK: - Derived

    var isActive: Bool { remainingSeconds != nil }

    /// True while an end-of-item policy (not the countdown) is armed.
    var endPolicyActive: Bool { endPolicy != .timed }

    /// End-of-item label while armed, for the trigger-button badge.
    var endPolicyLabel: String {
        switch endPolicy {
        case .timed:        return ""
        case .endOfTrack:   return "track"
        case .endOfEpisode: return "episode"
        case .endOfChapter: return "chapter"
        }
    }

    /// Short human-readable countdown for the inline badge: "30m", "1:45", etc.
    var displayRemaining: String {
        guard let secs = remainingSeconds else { return "" }
        let m = secs / 60
        let s = secs % 60
        return s == 0 ? "\(m)m" : "\(m):\(String(format: "%02d", s))"
    }

    // MARK: - Control

    /// Start (or restart) a countdown for `minutes` minutes.
    func set(minutes: Int) {
        guard minutes > 0 else { return }
        cancel()
        remainingSeconds = minutes * 60
        countdownTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
                let next = (self.remainingSeconds ?? 0) - 1
                if next <= 0 {
                    self.remainingSeconds = nil
                    self.onExpiry?()
                    return
                }
                self.remainingSeconds = next
            }
        }
    }

    /// Cancel and clear any running timer AND any armed end-of-item policy.
    func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
        remainingSeconds = nil
        endPolicy = .timed
        closeSheets()
    }

    /// Arm an end-of-item policy (and clear any running countdown — one sleep intent
    /// at a time, matching the web sheet's single-slot model).
    func setEndPolicy(_ policy: SleepTimerEndPolicy) {
        cancel()
        endPolicy = policy
    }

    /// Close BOTH sheet presentation paths (the trigger button's local @State cannot be
    /// reached from here; the deep-link path lives on the model). A stale path-binding
    /// behind a dismissed sheet is harmless and re-arms false on the next programmatic open.
    func closeSheets() { showSheet = false }
}

// MARK: - Presets

private let sleepPresets: [Int] = [15, 30, 45, 60, 90, 120]

private func presetLabel(_ minutes: Int) -> String {
    if minutes >= 60 {
        // Plural fix: 90 min rendered "1 hours". Whole hours pluralize correctly;
        // half-hour steps stay minutes (60 → "1 hour", 90 → "90 minutes", 120 → "2 hours").
        let hours = minutes / 60
        if minutes % 60 == 0 { return "\(hours) hour\(hours == 1 ? "" : "s")" }
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
    return "\(minutes) minute\(minutes == 1 ? "" : "s")"
}

// MARK: - SleepTimerSheet

/// Sheet content: preset list, custom input, and cancel (when active).
struct SleepTimerSheet: View {
    /// The player's "on" colour (the track colour) for the selected row's checkmark.
    var onColour: Color = KimaColor.textPrimary

    let model: SleepTimerModel
    @State private var customText = ""
    @Environment(\.dismiss) private var dismiss

    // Keyboard dismissal.
    // .numberPad has no Return key, so we provide an inline Done escape.
    @FocusState private var customFocused: Bool

    var body: some View {
        // Root stays a VStack (the route sheet's accessibility id resolves on VStack content);
        // the header is fixed and the rows scroll — eleven rows overflow the medium detent.
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack {
                Text("sleep timer")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .tracking(0.1)
                Spacer()
                Button { dismiss() } label: {
                    Text("done")
                        .kimaHitTarget()
                }
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.top, KimaSpacing.md)

            KimaHairline()
                .padding(.horizontal, KimaSpacing.lg)

            ScrollView {
                rows
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(KimaKeyboardTapCatcher())
    }

    @ViewBuilder
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Presets
            ForEach(sleepPresets, id: \.self) { mins in
                presetRow(mins)
            }

            KimaHairline()
                .padding(.horizontal, KimaSpacing.lg)

            // Custom minutes input
            HStack(spacing: KimaSpacing.md) {
                TextField("custom", text: $customText)
                    .keyboardType(.numberPad)
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textPrimary)
                    .tint(KimaColor.textPrimary)
                    .focused($customFocused)

                Text("min")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)

                // Explicit escape hatch (numberPad has no Return key) — same convention
                // as KimaSearchField's inline Done.
                if customFocused {
                    Button("done") { customFocused = false }
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textPrimary)
                        .buttonStyle(.plain)
                        .accessibilityLabel("dismiss keyboard")
                }

                Button("set") { applyCustom() }
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textPrimary)
                    .disabled(!isCustomValid)
            }
            .padding(.horizontal, KimaSpacing.lg)
            .frame(minHeight: 44)

            KimaHairline()
                .padding(.horizontal, KimaSpacing.lg)

            // End-of-item policies (beyond the web sheet): pause when the current item ends
            // naturally. Only the row for what is playing shows, plus one already armed.
            ForEach(endPolicyRows, id: \.label) { row in
                endPolicyRow(row.policy, label: row.label)
            }

            // Cancel (when a countdown is running or an end-of-item policy is armed)
            if model.isActive || model.endPolicyActive {
                KimaHairline()
                    .padding(.horizontal, KimaSpacing.lg)

                Button {
                    model.cancel()
                    dismiss()
                } label: {
                    Text("cancel timer")
                        .font(KimaType.body)
                        .foregroundStyle(KimaColor.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, KimaSpacing.md)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, KimaSpacing.lg)
    }

    // MARK: - Helpers

    private func presetRow(_ mins: Int) -> some View {
        optionRow(presetLabel(mins), isSelected: model.isActive && model.remainingSeconds == mins * 60,
                  id: presetRowId(mins)) { model.set(minutes: mins) }
    }

    private var endPolicyRows: [(policy: SleepTimerEndPolicy, label: String)] {
        let all: [(policy: SleepTimerEndPolicy, label: String)] = [
            (.endOfTrack, "end of track"), (.endOfEpisode, "end of episode"), (.endOfChapter, "end of chapter"),
        ]
        guard let playback = model.currentPlayback?() else { return all }
        let fits = SleepTimerEndPolicy.endOfItem(for: playback)
        return all.filter { $0.policy == fits || $0.policy == model.endPolicy }
    }

    private func endPolicyRow(_ policy: SleepTimerEndPolicy, label: String) -> some View {
        optionRow(label, isSelected: model.endPolicy == policy,
                  id: "sleep-policy-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))") {
            model.setEndPolicy(policy)
        }
    }

    /// One selectable row: runs `apply`, dismisses the sheet, and shows a checkmark when selected.
    private func optionRow(_ label: String, isSelected: Bool, id: String,
                           apply: @escaping () -> Void) -> some View {
        Button {
            apply()
            dismiss()
        } label: {
            HStack {
                Text(label)
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(onColour)
                }
            }
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.vertical, KimaSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// Stable AX id for the minute presets (the policy rows carry their own ids).
    private func presetRowId(_ mins: Int) -> String { "sleep-preset-\(mins)" }

    private var isCustomValid: Bool {
        guard let n = Int(customText) else { return false }
        return n >= 1 && n <= 480
    }

    private func applyCustom() {
        guard isCustomValid, let mins = Int(customText) else { return }
        model.set(minutes: mins)
        customText = ""
        dismiss()
    }
}

extension View {
    /// The sleep-timer sheet presented for the `kima://sleep-timer` route (shell and full player share it).
    func sleepTimerRouteSheet(isPresented: Binding<Bool>, model: SleepTimerModel, onColour: Color) -> some View {
        sheet(isPresented: isPresented) {
            SleepTimerSheet(onColour: onColour, model: model)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(KimaColor.surfaceRaised)
                .accessibilityIdentifier("sleep-timer-route-sheet")
        }
    }
}
