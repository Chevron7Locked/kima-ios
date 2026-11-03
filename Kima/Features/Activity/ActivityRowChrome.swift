import SwiftUI

// MARK: - Shared activity-row chrome

// MARK: - ActivityRowActionButton

/// Circular trailing action button (24pt disc in a 44pt touch target) for clear, retry, cancel
/// and mark-read. `isLoading` swaps the icon for a spinner and disables the button.
struct ActivityRowActionButton: View {
    let systemImage: String
    var accessibilityLabel: String = ""
    /// When true: shows a ProgressView and disables the button (used for retry/loading states).
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().controlSize(.mini).tint(KimaColor.textMuted)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(KimaColor.textMuted)
                }
            }
            .frame(width: 24, height: 24)
            .background(KimaColor.surface, in: Circle())
            .kimaHitTarget()
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(accessibilityLabel)
    }
}
