import SwiftUI

/// Pagination controls: First / Prev / [N / Total] / Next / Last. First and last are glyph-only so the row fits one line.
/// Only rendered when totalPages > 1.
struct PaginationView: View {
    let currentPage: Int
    let totalPages: Int
    let isLoading: Bool
    let onPage: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Rule above the bar, inset to the gutter like every other hairline.
            KimaHairline()
                .padding(.horizontal, KimaSpacing.lg)

            HStack(spacing: KimaSpacing.sm) {
                PagButton("first", systemImage: "chevron.backward.2", iconOnly: true) {
                    onPage(1)
                }
                .disabled(currentPage == 1 || isLoading)

                PagButton("previous", systemImage: "chevron.backward") {
                    onPage(max(1, currentPage - 1))
                }
                .disabled(currentPage == 1 || isLoading)

                Spacer()

                // Page indicator — amber current / muted total
                HStack(spacing: KimaSpacing.xs) {
                    Text("\(currentPage)")
                        .font(KimaType.bodyStrong.monospacedDigit())
                        .foregroundStyle(KimaColor.textPrimary)
                    Text("/")
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)
                    Text("\(totalPages)")
                        .font(KimaType.body.monospacedDigit())
                        .foregroundStyle(KimaColor.textSecondary)
                }
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.vertical, KimaSpacing.md)
                .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                        .strokeBorder(KimaColor.hairline, lineWidth: 2)
                )

                Spacer()

                PagButton("next", systemImage: "chevron.forward") {
                    onPage(min(totalPages, currentPage + 1))
                }
                .disabled(currentPage == totalPages || isLoading)

                PagButton("last", systemImage: "chevron.forward.2", iconOnly: true) {
                    onPage(totalPages)
                }
                .disabled(currentPage == totalPages || isLoading)
            }
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.vertical, KimaSpacing.lg)
        }
    }
}

// MARK: - PagButton

private struct PagButton: View {
    let label: String
    let systemImage: String
    /// Shows only the glyph; the label is still spoken.
    let iconOnly: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ label: String, systemImage: String, iconOnly: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.iconOnly = iconOnly
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: KimaSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                if !iconOnly {
                    Text(label)
                        .font(KimaType.meta)
                        .tracking(0.1)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(isEnabled ? KimaColor.textSecondary : KimaColor.textMuted.opacity(0.4))
            .padding(.horizontal, KimaSpacing.md)
            .frame(minWidth: KimaLayout.minTouchTarget)
            .frame(height: 44)
            .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                    .strokeBorder(KimaColor.hairline, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
