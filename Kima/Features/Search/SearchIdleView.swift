import SwiftUI

// MARK: - Idle prompt (before any search)
//
// One tappable row per search scope (`SearchFilter`) under the search field. Tapping pre-selects the
// scope and focuses the field.

struct SearchIdlePrompt: View {
    /// Called when the user taps a scope row — sets `SearchViewModel.activeFilter`
    /// and focuses the search field so they can start typing immediately.
    let onSelect: (SearchFilter) -> Void

    /// Mirrors `SearchView.filterChips`'s gating: the Soulseek row only appears once the
    /// server has confirmed the scope is available (`SearchViewModel.soulseekEnabled`).
    /// Defaults false so existing call sites (if any are added later) fail closed.
    var soulseekEnabled: Bool = false


    /// `SearchFilter.allCases`, minus `.soulseek` when the server has no Soulseek configured.
    private var visibleFilters: [SearchFilter] {
        SearchFilter.allCases.filter { $0 != .soulseek || soulseekEnabled }
    }

    var body: some View {
        ScrollView {
            entryRows
                .padding(.bottom, KimaSpacing.huge)
        }
    }

    // MARK: - Entry rows

    private var entryRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visibleFilters) { filter in
                Button { onSelect(filter) } label: {
                    entryRow(for: filter)
                }
                .buttonStyle(.plain)

                if filter != visibleFilters.last {
                    KimaHairline()
                        .padding(.leading, 52 + KimaSpacing.lg)
                }
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
    }

    private func entryRow(for filter: SearchFilter) -> some View {
        HStack(spacing: KimaSpacing.lg) {
            ZStack {
                Circle()
                    .fill(KimaColor.surface)
                    .frame(width: 52, height: 52)
                    .overlay(Circle().strokeBorder(KimaColor.hairline, lineWidth: 1))
                Image(systemName: filter.icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(KimaColor.textSecondary)
            }

            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(filter.label)
                    .font(KimaType.headline)
                    .foregroundStyle(KimaColor.textPrimary)
                    .tracking(0.1)
                Text(filter.idleDescription)
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KimaColor.textMuted)
        }
        .padding(.vertical, KimaSpacing.lg)
        .contentShape(Rectangle())
    }
}

// MARK: - No results view

struct SearchNoResultsView: View {
    let query: String

    var body: some View {
        VStack(spacing: KimaSpacing.lg) {
            ZStack {
                Circle()
                    .fill(KimaColor.surface)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().strokeBorder(KimaColor.hairline, lineWidth: 1))
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(KimaColor.textMuted)
            }

            VStack(spacing: KimaSpacing.sm) {
                Text("no results for \u{201c}\(query)\u{201d}")
                    .font(KimaType.headline)
                    .foregroundStyle(KimaColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("try a different search term.")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
            }
        }
        .padding(.horizontal, KimaSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
