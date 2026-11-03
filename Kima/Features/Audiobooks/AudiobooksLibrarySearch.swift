import SwiftUI

// MARK: — AudiobooksLibraryView: search bar + results

extension AudiobooksLibraryView {

    // MARK: Search text binding (instant client-side filter via ViewModel)

    var searchBinding: Binding<String> {
        Binding(
            get: { vm.searchText },
            set: { vm.setSearchText($0) }
        )
    }

    // MARK: Search bar widget
    // Shared KimaSearchField: focus, Return/Done/clear/tap-outside dismissal live there.

    @ViewBuilder
    var audiobooksSearchBar: some View {
        KimaSearchField(prompt: "search audiobooks", text: searchBinding)
    }

    // MARK: Search results area

    @ViewBuilder
    var searchResultsContent: some View {
        if vm.searchResults.isEmpty {
            VStack(spacing: KimaSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(KimaColor.textMuted)
                Text("no results")
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, KimaSpacing.huge)
        } else {
            booksGrid(vm.searchResults)
        }
        Spacer(minLength: KimaSpacing.huge)
    }
}
