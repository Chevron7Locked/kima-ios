import SwiftUI

/// The destructive end-of-list row: a plain danger-colored text row on the 16pt gutter, a
/// `huge` gap above it so it never sits beside a routine control, always confirming first.
/// Callers add any extra bottom padding or List-row modifiers themselves.
struct KimaDestructiveRow: View {
    let label: String
    var systemImage: String?
    let confirmTitle: String
    var confirmMessage: String?
    let confirmButton: String
    var cancelButton: String = "cancel"
    /// While true the row shows a spinner with `busyLabel` and ignores taps.
    var isBusy: Bool = false
    var busyLabel: String?
    /// Side gutter and gap above the row; a form that already supplies its own passes smaller values.
    var gutter: CGFloat = KimaSpacing.lg
    var topGap: CGFloat = KimaSpacing.huge
    let action: () -> Void

    @State private var confirming = false

    var body: some View {
        Button { confirming = true } label: {
            HStack(spacing: KimaSpacing.md) {
                if isBusy {
                    ProgressView().tint(KimaColor.danger).scaleEffect(0.85)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                }
                Text(isBusy ? (busyLabel ?? label) : label)
                    .font(KimaType.headline)
                Spacer(minLength: 0)
            }
            .foregroundStyle(KimaColor.danger)
            .padding(.vertical, KimaSpacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .padding(.horizontal, gutter)
        .padding(.top, topGap)
        .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button(confirmButton, role: .destructive, action: action)
            Button(cancelButton, role: .cancel) {}
        } message: {
            if let confirmMessage { Text(confirmMessage) }
        }
    }
}
