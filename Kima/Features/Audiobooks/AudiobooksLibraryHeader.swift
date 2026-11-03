import SwiftUI

// MARK: — AudiobooksLibraryView: editorial header + sort and shuffle controls
// Extension of AudiobooksLibraryView. The nav bar is hidden: libraryHeader is the shared KimaScreenHeader
// masthead with shuffleButton on its count line, and sortMenu ends the genre · series row. Sync runs on pull-to-refresh.

extension AudiobooksLibraryView {

    // MARK: Editorial header — same masthead as Library/Podcasts

    var libraryHeader: some View {
        KimaScreenHeader(
            title: "audiobooks",
            statValue: vm.filteredAndSorted.count,
            statLabel: "books"
        ) {
            shuffleButton
        }
    }

    // MARK: Sort (end of the genre · series row) · shuffle (end of the masthead's count line)

    var sortMenu: some View {
        Menu {
            ForEach(AudiobooksLibraryViewModel.SortMode.allCases) { mode in
                Button {
                    vm.sort = mode; vm.currentPage = 0
                } label: {
                    Label(mode.rawValue, systemImage: vm.sort == mode ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: KimaSpacing.xs) {
                Text("sort: \(vm.sort.rawValue)")
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(KimaColor.textFaint)
            }
            .font(KimaType.caption)
            .foregroundStyle(KimaColor.textSecondary)
            .kimaHitTarget(growsLayout: false)
        }

    }

    var shuffleButton: some View {
        Button {
            guard let book = vm.randomBook() else { return }
            toastCenter.show("playing \(book.title.lowercased())")
            Task { await env.player.playAudiobook(book, client: env.client) }
        } label: {
            Label("shuffle", systemImage: "shuffle")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
                .kimaHitTarget(growsLayout: false)
        }
        .buttonStyle(.plain)
        .disabled(vm.filteredAndSorted.isEmpty)
        .accessibilityHint("plays a random book you haven't finished")
    }
}
