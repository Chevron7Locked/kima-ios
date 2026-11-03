import SwiftUI

// MARK: - Search surface (shared)
//
// The results surface, shared so search renders inline on the More hub: you type in place and results replace
// the menu. The empty state belongs to the caller, so this file owns only the results.

/// The results surface: filter chips (once a search has run) + the state-driven content
/// (soulseek / loading / no-results / result sections). NO idle prompt — the caller owns the
/// empty state. Designed to be the SOLE scrolling region beneath a pinned `KimaSearchField`, so the
/// inner scroll views here are never nested inside another scroll.
struct SearchResultsArea: View {
    @Bindable var vm: SearchViewModel
    let onPlayTracks: ([Track], Int) -> Void
    let onPushRoute: (SearchRoute) -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            if vm.hasSearched {
                // Same segmented control as Library/Audiobooks. Soulseek appears only when the
                // server confirmed P2P is available (vm.soulseekEnabled).
                KimaSegmented(
                    options: SearchFilter.allCases
                        .filter { $0 != .soulseek || vm.soulseekEnabled }
                        .map { ($0, $0.label) },
                    selection: $vm.activeFilter
                )
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.bottom, KimaSpacing.sm)
            }
            contentArea
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if vm.activeFilter == .soulseek {
            SoulseekResultsView(vm: vm)
        } else if vm.isLoading && !vm.hasAnyResults {
            KimaLoadingState(text: "searching…") { vm.retrySearch(client: env.client) }
        } else if vm.hasSearched && !vm.isLoading && !vm.hasAnyResults && vm.searchFailed {
            KimaErrorState(message: "couldn't search. check your connection.") {
                vm.retrySearch(client: env.client)
            }
        } else if vm.hasSearched && !vm.isLoading && !vm.hasAnyResults {
            SearchNoResultsView(query: vm.query)
        } else if vm.hasAnyResults {
            ScrollView {
                SearchResultSections(
                    vm: vm,
                    onPlayTracks: onPlayTracks,
                    onPushRoute: onPushRoute
                )
            }
        } else {
            // Query typed but the debounced search hasn't landed yet — keep it quiet (350 ms).
            Color.clear.frame(maxWidth: .infinity).frame(height: 1)
        }
    }
}
