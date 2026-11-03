import SwiftUI

// MARK: - Navigation enum (used by AudiobooksLibraryView + AudiobookDetailView nav stack)

enum AudiobookNavDest: Hashable {
    case detail(id: String)
    case series(name: String)
}

// MARK: - AudiobooksLibraryView

/// Audiobook library: filter pills, sort, genre, series view, continue listening, grid + pagination.
///
/// Owns its own `NavigationStack` — present as a full-screen or tab child.
/// Internal navigation (→ detail, → series) is handled via `AudiobookNavDest`.
struct AudiobooksLibraryView: View {
    @Environment(AppEnvironment.self) var env
    @Environment(ToastCenter.self)    var toastCenter

    @State var vm       = AudiobooksLibraryViewModel()
    @State var navPath  = NavigationPath()

    private let pageSizeOptions = [25, 50, 100, 250]

    var body: some View {
        NavigationStack(path: $navPath) {
            mainContent
            // Nav bar hidden: the editorial header lives inside libraryScroll.
            .toolbar(.hidden, for: .navigationBar)
            // Pull-to-refresh syncs with the audiobook server, then re-runs the same full load the
            // initial `.task` uses — the VM replaces state wholesale, so pages can't duplicate. Load
            // failures land in `errorMessage`, which mainContent already renders as the error state.
            .refreshable {
                if vm.isConfigured { await vm.sync(client: env.client) } else { await vm.load(client: env.client) }
            }
            .navigationDestination(for: AudiobookNavDest.self) { dest in
                switch dest {
                case .detail(let id):    AudiobookDetailView(id: id)
                case .series(let name):  AudiobookSeriesView(name: name)
                }
            }
            .kimaScreenCanvas()
        }
        .publishesNavDepth(tab: .audiobooks, count: navPath.count, to: env.router)
        .task { await vm.load(client: env.client) }
        #if DEBUG
        .task(id: "kima-open-deeplink") {
            let want = DebugDeepLink.requested
            guard want == "audiobook" || want == "series" || want == "audiobook-in-progress" else { return }
            for _ in 0..<50 {
                if want == "series", let name = vm.seriesGroups.first?.name {
                    navPath.append(AudiobookNavDest.series(name: name)); return
                }
                // The first continue-listening book: one with saved progress, so its page shows the "•••" menu.
                if want == "audiobook-in-progress", let id = vm.continueListening.first?.id {
                    navPath.append(AudiobookNavDest.detail(id: id)); return
                }
                if want == "audiobook", let id = vm.filteredAndSorted.first?.id {
                    navPath.append(AudiobookNavDest.detail(id: id)); return
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        #endif
        .onChange(of: vm.syncMessage) { _, msg in
            if let msg { toastCenter.show(msg, style: .info) }
        }
    }

    // MARK: - Main content branch

    @ViewBuilder
    private var mainContent: some View {
        if vm.isLoading && vm.books.isEmpty {
            KimaLoadingState()
        } else if !vm.isConfigured {
            notConfiguredView
        } else if let err = vm.errorMessage, vm.books.isEmpty {
            errorView(err) { Task { await vm.load(client: env.client) } }
        } else {
            libraryScroll
                .kimaScrollTopGround()
        }
    }

    // MARK: - Scroll body

    private var libraryScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Editorial header — AudiobooksLibraryHeader.swift.
                libraryHeader

                // Search bar — always visible; search computed props live in AudiobooksLibrarySearch.swift.
                audiobooksSearchBar
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.bottom, KimaSpacing.sm)

                if vm.isSearchActive {
                    searchResultsContent
                } else {
                    // The continue-listening header brings its own 32pt top gap; only pad when
                    // the controls row follows directly (otherwise the two gaps stacked to ~60pt).
                    filterPillsRow
                        .padding(.horizontal, KimaSpacing.lg)
                        .padding(.top, KimaSpacing.xs)
                        .padding(.bottom, vm.visibleContinueListening.isEmpty ? KimaSpacing.xl : 0)

                    if !vm.visibleContinueListening.isEmpty {
                        continueListeningRail
                    }

                    controlsRow
                        .padding(.horizontal, KimaSpacing.lg)
                        .padding(.vertical, KimaSpacing.md)

                    if vm.groupBySeries {
                        seriesGrid
                    } else {
                        booksGrid(vm.pagedBooks)
                    }

                    paginationBar
                        .padding(.horizontal, KimaSpacing.lg)
                        .padding(.vertical, KimaSpacing.lg)

                    Spacer(minLength: KimaSpacing.lg)
                }
            }
            .kimaViewportWidth()
        }
        .scrollIndicators(.hidden)
        .kimaKeyboardSafeCanvas()
        .kimaMiniPlayerClearance()
    }

    // MARK: - Filter pills

    /// All / In Progress / Finished, using the shared `KimaSegmented` control (same as the
    /// Library's Artists/Albums/Tracks picker).
    private var filterPillsRow: some View {
        KimaSegmented(
            options: AudiobooksLibraryViewModel.FilterMode.allCases.map { ($0, $0.rawValue.lowercased()) },
            selection: Binding(
                get: { vm.filter },
                set: { vm.filter = $0; vm.currentPage = 0 }
            )
        )
    }

    // MARK: - Continue Listening rail

    private var continueListeningRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: "continue listening")
            KimaRail(tileWidth: 120) { width in
                ForEach(vm.visibleContinueListening) { item in
                    AudiobookCardView(
                        bookId: item.id,
                        coverId: item.coverUrl,
                        title: item.title,
                        author: item.author,
                        progressPct: item.progressPct,
                        isFinished: item.isFinished,
                        onPlay: {
                            // Continue-listening items are a lightweight summary — fetch the
                            // full Audiobook (tracks/sections) before handing off to the player.
                            Task { @MainActor in
                                guard let book = try? await env.client.getAudiobook(id: item.id) else { return }
                                await env.player.playAudiobook(book, client: env.client)
                            }
                        }
                    ) {
                        navPath.append(AudiobookNavDest.detail(id: item.id))
                    }
                    .frame(width: width)  // narrower than the main grid on compact width
                }
            }
        }
        .padding(.bottom, KimaSpacing.lg)  // gap before controls row
    }

    // MARK: - Controls row (genre + series toggle + count)

    private var controlsRow: some View {
        HStack(spacing: KimaSpacing.sm) {
            // Genre filter
            if !vm.allGenres.isEmpty {
                Menu {
                    Button("all genres") { vm.selectedGenre = nil; vm.currentPage = 0 }
                    Divider()
                    ForEach(vm.allGenres, id: \.self) { genre in
                        Button(genre.lowercased()) { vm.selectedGenre = genre; vm.currentPage = 0 }
                    }
                } label: {
                    HStack(spacing: KimaSpacing.xs) {
                        Text((vm.selectedGenre ?? "genre").lowercased())
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(KimaColor.textFaint)
                    }
                    .font(KimaType.caption)
                    .foregroundStyle(vm.selectedGenre != nil ? KimaColor.textPrimary : KimaColor.textSecondary)
                    .kimaHitTarget(growsLayout: false)
                }
            }

            // Series toggle: a quiet pill, ink on a faint fill when on.
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    vm.groupBySeries.toggle()
                    vm.currentPage = 0
                }
            } label: {
                Label("series", systemImage: "books.vertical")
                    .font(KimaType.caption)
                    .foregroundStyle(vm.groupBySeries ? KimaColor.textPrimary : KimaColor.textSecondary)
                    .padding(.horizontal, KimaSpacing.md)
                    .padding(.vertical, KimaSpacing.sm)
                    .background(vm.groupBySeries ? KimaColor.fillQuiet : Color.clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(KimaColor.hairline, lineWidth: 1))
                    .kimaHitTarget(growsLayout: false)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(vm.groupBySeries ? .isSelected : [])

            Spacer()

            // The count lives in the masthead; this end of the row holds sort.
            sortMenu
        }
    }

    // MARK: - Books grid

    /// A grid of book cards: the library page and the search results both use it.
    func booksGrid(_ books: [Audiobook]) -> some View {
        return KimaCardGrid(count: books.count, minimum: 148, alignment: .leading) {
            ForEach(books) { book in
                AudiobookCardView(
                    bookId: book.id,
                    coverId: book.coverUrl,
                    title: book.title,
                    author: book.author,
                    progressPct: book.progress?.progress,
                    isFinished: book.progress?.isFinished ?? false,
                    onPlay: { Task { await env.player.playAudiobook(book, client: env.client) } }
                ) {
                    navPath.append(AudiobookNavDest.detail(id: book.id))
                }
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.bottom, KimaSpacing.lg)
    }

    // MARK: - Series grid

    private var seriesGrid: some View {
        return KimaCardGrid(count: vm.seriesGroups.count, minimum: 148, alignment: .leading) {
            ForEach(vm.seriesGroups, id: \.name) { group in
                let first = group.books.first
                let n = group.books.count
                // Play badge starts the first book in the series; nil (no badge) if empty.
                let playFirst: (() -> Void)? = first.map { book in
                    { Task { await env.player.playAudiobook(book, client: env.client) } }
                }
                AudiobookCardView(
                    bookId: group.name,
                    coverId: first?.coverUrl,
                    title: group.name,
                    author: "\(n) book\(n == 1 ? "" : "s")",
                    progressPct: nil,
                    isFinished: false,
                    onPlay: playFirst
                ) {
                    navPath.append(AudiobookNavDest.series(name: group.name))
                }
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.bottom, KimaSpacing.lg)
    }

    // MARK: - Pagination bar

    private var paginationBar: some View {
        HStack(spacing: KimaSpacing.md) {
            // Page size menu
            Menu {
                ForEach(pageSizeOptions, id: \.self) { size in
                    Button("\(size) per page") {
                        vm.pageSize = size
                        vm.currentPage = 0
                    }
                }
            } label: {
                Text("\(vm.pageSize)/page")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
            }

            Spacer()

            // Prev
            Button {
                withAnimation { vm.currentPage = max(0, vm.currentPage - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(vm.currentPage == 0 ? KimaColor.textMuted : KimaColor.textPrimary)
            }
            .disabled(vm.currentPage == 0)

            Text("\(vm.currentPage + 1) / \(vm.totalPages)")
                .font(KimaType.caption.monospacedDigit())
                .foregroundStyle(KimaColor.textSecondary)

            // Next
            Button {
                withAnimation { vm.currentPage = min(vm.totalPages - 1, vm.currentPage + 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        vm.currentPage >= vm.totalPages - 1 ? KimaColor.textMuted : KimaColor.textPrimary
                    )
            }
            .disabled(vm.currentPage >= vm.totalPages - 1)
        }
    }

    // Nav bar is hidden — the masthead, sort and shuffle live in AudiobooksLibraryHeader.swift; sync runs on pull-to-refresh.

    // Empty / error states extracted to AudiobooksLibraryStates.swift
}
