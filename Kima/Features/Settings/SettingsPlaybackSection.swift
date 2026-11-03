import SwiftUI

// MARK: - Playback

/// Settings section for audio/streaming preferences.
/// Reads and writes `UserPreferences.shared` (persisted to UserDefaults) and also updates
/// the live `PlaybackController` instance for speed changes that should take effect immediately.
struct PlaybackSection: View {
    @Bindable var prefs: UserPreferences
    let player: PlaybackController
    @Environment(AppEnvironment.self) private var env
    /// Admin (role == "admin") sees the server-wide queue limit; web hides
    /// the row entirely for everyone else.
    var isAdmin: Bool = false
    /// Queue-limit slice of /system-settings, loaded only for admins.
    @State private var queueLimit: Int?
    @State private var queueText: String = ""
    @State private var queueSaving = false

    private static let speedSteps: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        KimaSectionHeader(title: "playback")

        VStack(alignment: .leading, spacing: 0) {
            // Audiobook speed — writes prefs AND updates the live player instance.
            SpeedRow(
                label: "audiobook speed",
                steps: Self.speedSteps,
                value: prefs.defaultAudiobookSpeed
            ) { newSpeed in
                prefs.defaultAudiobookSpeed = newSpeed
                player.audiobookSpeed = newSpeed
            }

            KimaHairline()

            // Podcast speed — same live-update pattern.
            SpeedRow(
                label: "podcast speed",
                steps: Self.speedSteps,
                value: prefs.defaultPodcastSpeed
            ) { newSpeed in
                prefs.defaultPodcastSpeed = newSpeed
                player.podcastSpeed = newSpeed
            }

            // Queue limit — server-wide, so only admins see the row (web parity: hidden, not disabled).
            // Sent as typed; the server validates 100...100000 and echoes the stored value.
            if isAdmin {
                KimaHairline()
                VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                    Text("queue limit")
                        .font(KimaType.body)
                        .foregroundStyle(KimaColor.textPrimary)
                    Text("max tracks in the play queue (100 to 100,000).")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                    HStack(spacing: KimaSpacing.md) {
                        TextField("", text: $queueText)
                            .textFieldStyle(.plain)
                            .font(KimaType.body)
                            .foregroundStyle(KimaColor.textPrimary)
                            .keyboardType(.numberPad)
                            .monospacedDigit()
                            .accessibilityIdentifier("queue-limit-field")
                            .padding(KimaSpacing.md)
                            .background(KimaColor.surfaceRaised, in: RoundedRectangle(cornerRadius: KimaRadius.card))
                            .overlay(
                                RoundedRectangle(cornerRadius: KimaRadius.card)
                                    .strokeBorder(KimaColor.hairline, lineWidth: 1)
                            )
                            .frame(maxWidth: 140)
                        Button(queueSaving ? "saving…" : "save") { commitQueueLimit() }
                            .font(KimaType.headline)
                            .foregroundStyle(KimaColor.textSecondary)
                            .buttonStyle(.plain)
                            .disabled(queueSaving)
                            .accessibilityIdentifier("queue-limit-save")
                        Spacer()
                    }
                }
                .padding(.vertical, KimaSpacing.lg)
            }
          }
          .padding(.horizontal, KimaSpacing.lg)
          .task(id: isAdmin) {
              guard isAdmin, queueLimit == nil else { return }
              if let s = try? await env.client.getSystemQueueLimit() {
                  queueLimit = s.maxQueueLength
                  queueText = String(s.maxQueueLength)
              }
          }
      }

    private func commitQueueLimit() {
        guard let n = Int(queueText.filter(\.isNumber)), n > 0 else { return }
        queueSaving = true
        Task {
            defer { queueSaving = false }
            // Values pass up unclamped as typed (web parity); the server
            // validates and echoes the stored row, which we render from.
            if let s = try? await env.client.updateSystemQueueLimit(n) {
                queueLimit = s.maxQueueLength
                queueText = String(s.maxQueueLength)
            } else {
                queueText = queueLimit.map(String.init) ?? queueText
            }
        }
    }
  }

// MARK: - Shared toggle row

/// Labeled two-line toggle — label + muted caption, amber tint. Used by the scrobbling toggles.
struct SettingsToggleRow: View {
    let label: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(label)
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textPrimary)
                Text(caption)
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
            }
        }
        .tint(KimaColor.brand)
        .padding(.vertical, KimaSpacing.lg)
    }
}

// MARK: - Speed row

/// Inline [−] value [+] row for selecting a speed from a fixed step list.
private struct SpeedRow: View {
    let label: String
    let steps: [Float]
    let value: Float
    let onChange: (Float) -> Void

    private var currentIdx: Int {
        steps.firstIndex(of: value) ?? steps.firstIndex(of: 1.0) ?? 1
    }

    var body: some View {
        HStack {
            Text(label)
                .font(KimaType.body)
                .foregroundStyle(KimaColor.textPrimary)

            Spacer(minLength: 0)

            HStack(spacing: KimaSpacing.xs) {
                Button {
                    onChange(steps[max(currentIdx - 1, 0)])
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(currentIdx == 0 ? KimaColor.textMuted : KimaColor.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(KimaColor.surfaceRaised, in: Circle())
                        .kimaHitTarget()
                }
                .buttonStyle(.plain)
                .disabled(currentIdx == 0)

                Text(String(format: "%g×", value))
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textPrimary)
                    .monospacedDigit()
                    .frame(minWidth: 38)

                Button {
                    onChange(steps[min(currentIdx + 1, steps.count - 1)])
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            currentIdx == steps.count - 1 ? KimaColor.textMuted : KimaColor.textPrimary
                        )
                        .frame(width: 28, height: 28)
                        .background(KimaColor.surfaceRaised, in: Circle())
                        .kimaHitTarget()
                }
                .buttonStyle(.plain)
                .disabled(currentIdx == steps.count - 1)
            }
        }
        .padding(.vertical, KimaSpacing.xs)
    }
}
