import SwiftUI

// MARK: - PlayerSecondaryButton
// Secondary-controls button (icon over a small label) for PlayerTransportControls and SleepTimerButton. Active is
// the track colour, idle is textMuted; a spinner replaces the icon while `loading`. `.monospacedDigit()` steadies the countdown.

/// A secondary player control: icon above label, fixed 48 pt height, in the track colour when active.
struct PlayerSecondaryButton: View {
    @Environment(AppEnvironment.self) private var env
    let icon: String
    let label: String
    var active: Bool = false
    var loading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: KimaSpacing.xs) {
                ZStack {
                    if loading {
                        ProgressView().tint(env.accent.color)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                    }
                }
                .frame(height: 22)

                Text(label)
                    .font(KimaType.metaStrong)
                    .tracking(0.1)
                    .monospacedDigit()
            }
            .foregroundStyle(active ? env.accent.color : KimaColor.textMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .accessibilityLabel("\(label)\(active ? ", on" : "")")
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}
