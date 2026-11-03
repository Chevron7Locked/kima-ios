import SwiftUI

// MARK: - KimaToastView

/// Transient banner. Do not instantiate directly from feature code: post via `ToastCenter.show(_:style:)` and let
/// `KimaToastOverlay` drive visibility. A `surfaceRaised` rounded rect with a 1 px hairline, a leading SF Symbol
/// (green checkmark success, red exclamation error, muted info), wrapping caption text, and a shadow.
private struct KimaToastView: View {
    let data: KimaToastData
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: KimaSpacing.sm) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            Text(data.message.lowercased())
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let action = data.action {
                Spacer(minLength: KimaSpacing.sm)
                Button(action.label, action: onAction)
                    .font(KimaType.captionStrong)
                    .foregroundStyle(KimaColor.textPrimary)
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("toast-action")
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                .fill(KimaColor.surfaceRaised)
                .shadow(color: .black.opacity(0.30), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                .strokeBorder(KimaColor.hairline, lineWidth: 1)
        )
    }

    // MARK: Style-keyed assets

    private var iconName: String {
        switch data.style {
        case .success: return "checkmark.circle.fill"
        case .error:   return "exclamationmark.circle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch data.style {
        case .success: return KimaColor.positive   // fixed green — confirmed / success
        case .error:   return KimaColor.danger     // fixed red — failure / destructive
        case .info:    return KimaColor.textMuted
        }
    }
}

// MARK: - KimaToastOverlay

/// Full-height transparent overlay, the topmost child of AppShellView's root ZStack; observes `ToastCenter` and shows/hides the banner.
/// Slides in below the status bar (plain opacity under Reduce Motion). Touches pass through, like the web's
/// non-blocking toasts, except on a toast that has a button.
struct KimaToastOverlay: View {
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if let toast = toastCenter.current {
                KimaToastView(data: toast) { toastCenter.performAction() }
                    // Only a toast with a button takes touches; the rest pass through.
                    .allowsHitTesting(toast.action != nil)
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.top, KimaSpacing.sm)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
            }
            Spacer()
        }
        .animation(
            .spring(response: 0.35, dampingFraction: 0.85),
            value: toastCenter.current
        )
    }
}
