import SwiftUI

// MARK: - PodcastCategoryPills

/// Up to four of a show's Apple categories as plain text pills; a pill opens that category's chart.
struct PodcastCategoryPills: View {
    let categories: [PodcastCategoryRef]
    let onTap: (Int) -> Void

    var body: some View {
        if !categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KimaSpacing.sm) {
                    ForEach(categories.prefix(4)) { category in
                        Button { onTap(category.id) } label: {
                            Text(category.name.lowercased())
                                .font(KimaType.caption)
                                .foregroundStyle(KimaColor.textSecondary)
                                .padding(.horizontal, KimaSpacing.md)
                                .frame(minHeight: 32)
                                .overlay(Capsule().strokeBorder(KimaColor.hairlineStrong, lineWidth: 1))
                                .kimaHitTarget(growsLayout: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("opens the \(category.name.lowercased()) chart")
                    }
                }
                .padding(.horizontal, KimaSpacing.lg)
            }
        }
    }
}

// MARK: - PodcastChartDestination

/// A chart page pushed from a show page, which may sit in any tab's stack: it pushes the shows it lists itself.
struct PodcastChartDestination: View {
    let categoryId: Int?
    @State private var showId: String?

    var body: some View {
        PodcastChartView(categoryId: categoryId) { showId = $0.id }
            .navigationDestination(item: $showId) { PodcastDetailView(id: $0) }
    }
}
