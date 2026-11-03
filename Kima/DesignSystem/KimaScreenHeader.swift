import SwiftUI

/// Shared masthead for the top-level library screens (Library, Audiobooks, Podcasts): a
/// left-aligned lowercase Bricolage title with an optional small count beneath it, and an optional
/// quiet control at the end of the count line (below the activity bell, so it never sits under it).
struct KimaScreenHeader<Trailing: View>: View {
    /// Title, shown lowercased (e.g. "library").
    let title: String
    /// Collection count — shown small + muted BENEATH the title, NOT a vanity stat card. Optional:
    /// omit it on screens with no MEANINGFUL count (Settings / More), where a "9 SECTIONS"-style
    /// figure would just be filler — the title stands alone.
    var statValue: Int? = nil
    /// Unit label after the count (e.g. "artists", "books", "shows"), paired with `statValue`.
    var statLabel: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            KimaScreenTitle(title: title)

            // Count sits beneath the title, clear of the activity bell floating top-right. Hidden when there is no count.
            if let statValue, let statLabel {
                HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.xs) {
                    Text(statValue.formatted())
                        .font(KimaType.captionStrong)
                        .foregroundStyle(KimaColor.textSecondary)
                        .monospacedDigit()
                    Text(statLabel.lowercased())
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                    Spacer(minLength: KimaSpacing.md)
                    trailing()
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.top, KimaSpacing.md)
        .padding(.bottom, KimaSpacing.md)
    }
}

extension KimaScreenHeader where Trailing == EmptyView {
    init(title: String, statValue: Int? = nil, statLabel: String? = nil) {
        self.init(title: title, statValue: statValue, statLabel: statLabel, trailing: { EmptyView() })
    }
}

/// The page title in the masthead style (lowercase Bricolage page title, shrinks to fit rather than truncate), for pages that
/// lay out their own masthead row, such as a sheet with its close button beside the title.
struct KimaScreenTitle: View {
    let title: String

    var body: some View {
        Text(title.lowercased())
            .font(KimaType.pageTitle)
            .foregroundStyle(KimaColor.textPrimary)
            .tracking(-0.4)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
