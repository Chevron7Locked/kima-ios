import SwiftUI

// MARK: - LongFormSkipButton

/// One ±30 s skip button for audiobooks and podcasts. It fills its column, so the long-form
/// secondary row (back · forward · speed · sleep) splits into equal columns like the music row.
/// Uses the same 200 ms debounce accumulator as music ±N skip (`player.skip(by:)`).
struct LongFormSkipButton: View {
    @Environment(PlaybackController.self) private var player
    let seconds: Double

    var body: some View {
        Button { player.skip(by: seconds) } label: {
            VStack(spacing: KimaSpacing.xs) {
                Image(systemName: seconds < 0 ? "gobackward.30" : "goforward.30")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(KimaColor.textPrimary)
                Text("30")
                    .font(KimaType.meta.monospacedDigit())
                    .foregroundStyle(KimaColor.textMuted)
                    .tracking(0.5)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seconds < 0 ? "skip back 30 seconds" : "skip forward 30 seconds")
    }
}

// MARK: - SpeedPickerButton

/// Labeled speed control for long-form content.
/// Shows the current rate (e.g. "1.25×") and presents a popover picker on tap.
/// Rates: 0.75, 1.0, 1.25, 1.5, 1.75, 2.0 — persisted per-type in UserDefaults.
struct SpeedPickerButton: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast
    @State private var showPicker = false

    static let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private var currentSpeed: Float {
        switch player.playbackType {
        case .audiobook:       return player.audiobookSpeed
        case .podcastEpisode:  return player.podcastSpeed
        case .track:           return 1.0
        }
    }

    var body: some View {
        Button { showPicker = true } label: {
            VStack(spacing: KimaSpacing.xs) {
                Text(rateLabel(currentSpeed))
                    .font(KimaType.bodyStrong)
                    .monospacedDigit()
                    .foregroundStyle(currentSpeed == 1.0 ? KimaColor.textMuted : env.accent.color)
                    .frame(height: 22)
                Text("speed")
                    .font(KimaType.metaStrong)
                    .tracking(0.1)
                    .foregroundStyle(currentSpeed == 1.0 ? KimaColor.textMuted : env.accent.color)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("playback speed: \(rateLabel(currentSpeed))")
        .popover(isPresented: $showPicker, attachmentAnchor: .point(.top)) {
            speedPickerContent
                .appEnvironment(env, toast)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var speedPickerContent: some View {
        VStack(spacing: 0) {
            Text("playback speed")
                .font(KimaType.metaStrong)
                .tracking(0.1)
                .foregroundStyle(KimaColor.textMuted)
                .padding(.top, KimaSpacing.lg)
                .padding(.bottom, KimaSpacing.sm)

            ForEach(Self.rates, id: \.self) { rate in
                Button {
                    player.setLongFormSpeed(rate)
                    showPicker = false
                } label: {
                    HStack {
                        Text(rateLabel(rate))
                            .font(rate == currentSpeed ? KimaType.bodyStrong : KimaType.body)
                            .monospacedDigit()
                            .foregroundStyle(rate == currentSpeed ? env.accent.color : KimaColor.textPrimary)
                        Spacer()
                        if rate == currentSpeed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(env.accent.color)
                        }
                    }
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.vertical, KimaSpacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if rate != Self.rates.last {
                    KimaHairline()
                        .padding(.horizontal, KimaSpacing.lg)
                }
            }
        }
        .padding(.bottom, KimaSpacing.sm)
        .frame(width: 180)
        .background(KimaColor.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous))
    }

    private func rateLabel(_ rate: Float) -> String {
        // Show one decimal place only when not a whole number
        rate.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(rate))×"
            : String(format: "%g×", rate)
    }
}
