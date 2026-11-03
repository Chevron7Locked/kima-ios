import SwiftUI

// Subviews for MoreView — the editorial replacement for iOS's auto-generated "More" overflow.
// Kept in a separate file (MoreView.swift stays a thin layout + navigation-wiring shell).

// MARK: - MoreRow

/// One directory entry: bare muted glyph + bold label + one-line description + chevron.
/// Rows stack inside a `MoreSection`, which puts them on the gutter; each row draws its own
/// hairline divider (gutter to gutter, like the Settings rows).
struct MoreRow: View {
    let icon: String
    let title: String
    let description: String
    /// False for the last row in a group (no trailing divider).
    var showDivider: Bool = true
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: KimaSpacing.md) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(KimaColor.textSecondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                        Text(title.lowercased())
                            .font(KimaType.headline)
                            .foregroundStyle(KimaColor.textPrimary)
                        Text(description.lowercased())
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textMuted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KimaColor.textMuted)
                }
                .padding(.vertical, KimaSpacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDivider {
                KimaHairline()
            }
        }
    }
}

// MARK: - MoreSection

/// Setlist-style group: `KimaSectionHeader` + its hairline-separated rows on the gutter, the
/// same structure as the Settings sections so the hub reads as a sibling of the screen it
/// links to at the bottom.
struct MoreSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        KimaSectionHeader(title: title)
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, KimaSpacing.lg)
    }
}
