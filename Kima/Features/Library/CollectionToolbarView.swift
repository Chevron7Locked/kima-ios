import SwiftUI

/// Collection toolbar: one row under the tab picker — search field, filter button (opens the Refine
/// panel: filter + sort + per-page) and a quiet labeled shuffle.
///
/// Layout: [search ··········] [filter] [shuffle]
struct CollectionToolbarView: View {
    let activeTab: CollectionTab
    /// The library search string. The field is a child view that owns its own focus, so focusing it
    /// re-renders only the field.
    @Binding var searchText: String
    @Binding var filter: LibraryFilter
    @Binding var sortBy: LibrarySortOption
    @Binding var itemsPerPage: Int
    let isShuffling: Bool
    let onShuffle: () -> Void
    let onRefinementChanged: () -> Void  // caller reloads after any change

    @State private var showRefine = false

    private var hasNonDefaultRefinements: Bool {
        filter != .owned || sortBy != .name || itemsPerPage != 40
    }

    /// The filter square reads as on while its panel is open or a refinement is set.
    private var filterLit: Bool { showRefine || hasNonDefaultRefinements }

    private var availableSortOptions: [LibrarySortOption] {
        LibrarySortOption.allCases.filter { $0.available(for: activeTab) }
    }

    var body: some View {
        HStack(spacing: KimaSpacing.sm) {
            KimaSearchField(prompt: "search library", text: $searchText)

            // Filter: a field-height square beside the search; a dot marks a non-default refinement.
            Button {
                showRefine.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(filterLit ? KimaColor.brand : KimaColor.textSecondary)
                    .frame(width: KimaLayout.minTouchTarget, height: KimaLayout.minTouchTarget)
                    .background(
                        filterLit ? KimaColor.brand.opacity(0.12) : KimaColor.surface,
                        in: RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                            .strokeBorder(filterLit ? KimaColor.brand.opacity(0.4) : KimaColor.hairline,
                                          lineWidth: 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        if hasNonDefaultRefinements {
                            Circle().fill(KimaColor.brand).frame(width: 6, height: 6).padding(KimaSpacing.sm)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("filter and sort")
            .accessibilityValue(hasNonDefaultRefinements ? "changed" : "")

            // Shuffle Library — quiet and labeled; amber is kept for a page's one primary play.
            KimaActionPill(title: "shuffle", systemImage: "shuffle", isLoading: isShuffling, action: onShuffle)
                .accessibilityHint("plays your whole library in random order")
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.sm)
        .sheet(isPresented: $showRefine) {
            RefineSheetView(
                activeTab: activeTab,
                filter: $filter,
                sortBy: $sortBy,
                itemsPerPage: $itemsPerPage,
                availableSortOptions: availableSortOptions,
                onApply: onRefinementChanged
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(KimaColor.surfaceRaised)
        }
    }
}

// MARK: - RefineSheetView

/// Bottom sheet with filter / sort / per-page pickers.
private struct RefineSheetView: View {
    let activeTab: CollectionTab
    @Binding var filter: LibraryFilter
    @Binding var sortBy: LibrarySortOption
    @Binding var itemsPerPage: Int
    let availableSortOptions: [LibrarySortOption]
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let perPageOptions = [24, 40, 80, 200]
    private var showFilter: Bool { activeTab != .tracks }

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xl) {
            // Sheet handle + header
            HStack {
                Text("filter")
                    .font(KimaType.meta)
                    .foregroundStyle(KimaColor.textMuted)
                    .tracking(0.1)
                Spacer()
                KimaCloseButton(label: "close", id: "library-filter-close", kind: .screen) { dismiss() }
            }
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.top, KimaSpacing.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: KimaSpacing.xxl) {
                    // Filter section (hidden for Tracks tab)
                    if showFilter {
                        RefineSection(label: "show") {
                            VStack(spacing: KimaSpacing.sm) {
                                ForEach(LibraryFilter.allCases) { opt in
                                    FilterOptionButton(
                                        option: opt,
                                        isActive: filter == opt,
                                        action: {
                                            filter = opt
                                            onApply()
                                        }
                                    )
                                }
                            }
                        }
                    }

                    // Sort section
                    RefineSection(label: "sort by") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                                  spacing: KimaSpacing.sm) {
                            ForEach(availableSortOptions) { opt in
                                SortOptionButton(
                                    option: opt,
                                    isActive: sortBy == opt,
                                    action: {
                                        sortBy = opt
                                        onApply()
                                    }
                                )
                            }
                        }
                    }

                    // Per-page section
                    RefineSection(label: "per page") {
                        HStack(spacing: KimaSpacing.sm) {
                            ForEach(perPageOptions, id: \.self) { n in
                                PerPageButton(
                                    count: n,
                                    isActive: itemsPerPage == n,
                                    action: {
                                        itemsPerPage = n
                                        onApply()
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.bottom, KimaSpacing.huge)
            }
        }
    }
}

// MARK: - Sub-components

private struct RefineSection<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            Text(label)
                .font(KimaType.meta)
                .foregroundStyle(KimaColor.textMuted)
                .tracking(0.1)
            content
        }
    }
}

private struct FilterOptionButton: View {
    let option: LibraryFilter
    let isActive: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(option.label)
                    .font(KimaType.captionStrong)
                    .foregroundStyle(isActive ? KimaColor.brand : KimaColor.textPrimary)
                    .tracking(0.1)
                Text(option.description)
                    .font(KimaType.meta)
                    .foregroundStyle(KimaColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, KimaSpacing.md)
            .padding(.vertical, KimaSpacing.md)
            .refineChip(isActive: isActive)
        }
        .buttonStyle(.plain)
    }
}

private struct SortOptionButton: View {
    let option: LibrarySortOption
    let isActive: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(option.label)
                .font(KimaType.metaStrong)
                .foregroundStyle(isActive ? KimaColor.brand : KimaColor.textSecondary)
                .tracking(0.1)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .refineChip(isActive: isActive)
        }
        .buttonStyle(.plain)
    }
}

private struct PerPageButton: View {
    let count: Int
    let isActive: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("\(count)")
                .font(KimaType.captionStrong.monospacedDigit())
                .foregroundStyle(isActive ? KimaColor.brand : KimaColor.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .refineChip(isActive: isActive)
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func refineChip(isActive: Bool) -> some View {
        background(
            isActive ? KimaColor.brand.opacity(0.1) : KimaColor.surface,
            in: RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                .strokeBorder(isActive ? KimaColor.brand.opacity(0.4) : KimaColor.hairline, lineWidth: 1)
        )
    }
}
