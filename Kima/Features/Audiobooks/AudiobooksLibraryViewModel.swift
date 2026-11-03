import Foundation
import Observation

// MARK: - Filter / Sort enums (nested in the VM's namespace via extension)

extension AudiobooksLibraryViewModel {

    enum FilterMode: String, CaseIterable, Identifiable {
        case all      = "All"
        case listening = "In Progress"
        case finished = "Finished"
        var id: String { rawValue }
    }

    enum SortMode: String, CaseIterable, Identifiable {
        case title         = "title"
        case author        = "author"
        case recentlyPlayed = "recently played"
        case series        = "series"
        var id: String { rawValue }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class AudiobooksLibraryViewModel {

    // MARK: Raw state

    var books: [Audiobook] = []          { didSet { _filteredAndSortedDirty = true } }
    var continueListening: [AudiobookContinueItem] = []
    var isConfigured = true
    var isLoading    = false
    var errorMessage: String? = nil

    // MARK: Filter / Sort / Pagination state

    var filter:        FilterMode = .all { didSet { _filteredAndSortedDirty = true } }
    var sort:          SortMode   = .title { didSet { _filteredAndSortedDirty = true } }
    var selectedGenre: String?    = nil  { didSet { _filteredAndSortedDirty = true } }
    var groupBySeries  = false

    // MARK: filteredAndSorted memo cache

    /// The cache backing `filteredAndSorted`. @ObservationIgnored — SwiftUI tracking is
    /// maintained by "touching" the tracked input properties inside the computed getter.
    @ObservationIgnored private var _filteredAndSortedCache: [Audiobook] = []
    @ObservationIgnored private var _filteredAndSortedDirty = true
    var pageSize       = 50
    var currentPage    = 0

    // MARK: Sync state

    var isSyncing   = false
    var syncMessage: String? = nil

    // MARK: Search state

    var searchText:    String     = ""
    var searchResults: [Audiobook] = []

    var isSearchActive: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Computed: filter + sort pipeline

    var allGenres: [String] {
        let flat = books.flatMap { $0.genres ?? [] }
        return Array(Set(flat)).sorted()
    }

    /// Filter + sort pipeline over `books`, cached until an input changes.
    /// The getter touches each tracked input so @Observable re-subscribes after every cache hit; when an input
    /// changes, `_filteredAndSortedDirty` is already true via `didSet`.
    var filteredAndSorted: [Audiobook] {
        // Maintain @Observable subscriptions even on cache hits.
        _ = books.isEmpty; _ = filter; _ = sort; _ = selectedGenre
        if !_filteredAndSortedDirty { return _filteredAndSortedCache }
        _filteredAndSortedCache = computeFilteredAndSorted()
        _filteredAndSortedDirty = false
        return _filteredAndSortedCache
    }

    private func computeFilteredAndSorted() -> [Audiobook] {
        var result = books

        // 1. Filter
        switch filter {
        case .all: break
        case .listening:
            result = result.filter {
                ($0.progress?.progress ?? 0) > 0 && !($0.progress?.isFinished ?? false)
            }
        case .finished:
            result = result.filter { $0.progress?.isFinished == true }
        }

        // 2. Genre
        if let genre = selectedGenre {
            result = result.filter { $0.genres?.contains(genre) == true }
        }

        // 3. Sort
        switch sort {
        case .title:
            result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .author:
            result.sort { $0.author.localizedCompare($1.author) == .orderedAscending }
        case .recentlyPlayed:
            result.sort {
                ($0.progress?.lastPlayedAt ?? .distantPast) >
                ($1.progress?.lastPlayedAt ?? .distantPast)
            }
        case .series:
            result.sort {
                let n0 = $0.series?.name ?? "\u{fffd}"
                let n1 = $1.series?.name ?? "\u{fffd}"
                if n0 != n1 { return n0.localizedCompare(n1) == .orderedAscending }
                let s0 = Double($0.series?.sequence ?? "0") ?? 0
                let s1 = Double($1.series?.sequence ?? "0") ?? 0
                return s0 < s1
            }
        }
        return result
    }

    var totalPages: Int {
        let count = filteredAndSorted.count
        return count == 0 ? 1 : (count + pageSize - 1) / pageSize
    }

    var pagedBooks: [Audiobook] {
        let all = filteredAndSorted
        let start = currentPage * pageSize
        guard start < all.count else { return [] }
        return Array(all[start..<min(start + pageSize, all.count)])
    }

    /// Continue listening visible only when "All" filter, not grouped by series, and not searching.
    var visibleContinueListening: [AudiobookContinueItem] {
        guard filter == .all && !groupBySeries && !isSearchActive else { return [] }
        return continueListening
    }

    /// Series groups for groupBySeries mode.
    var seriesGroups: [(name: String, books: [Audiobook])] {
        var map: [String: [Audiobook]] = [:]
        for book in filteredAndSorted {
            guard let sName = book.series?.name else { continue }
            map[sName, default: []].append(book)
        }
        return map
            .map { (name: $0.key, books: $0.value) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // MARK: - Actions

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// Loads the library. A call while a load is running (pull-to-refresh during the first load)
    /// waits for that load instead of being dropped.
    func load(client: KimaAPIClient) async {
        if let loadTask { return await loadTask.value }
        let task = Task { [weak self] in
            await self?.fetch(client: client)
            self?.loadTask = nil
        }
        loadTask = task
        await task.value
    }

    private func fetch(client: KimaAPIClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let booksTask   = client.getAudiobooks()
            async let clTask      = client.getContinueListeningAudiobooks()
            let (listResult, clItems) = try await (booksTask, clTask)
            switch listResult {
            case .configured(let loaded):
                books        = loaded
                isConfigured = true
            case .notConfigured:
                books        = []
                isConfigured = false
            }
            continueListening = clItems.filter { !$0.isFinished }
            currentPage = min(currentPage, max(totalPages - 1, 0))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sync(client: KimaAPIClient) async {
        // A pull during a running sync waits for that sync's reload instead of returning at once.
        guard !isSyncing else { await loadTask?.value; return }
        isSyncing = true
        syncMessage = nil
        defer { isSyncing = false }
        do {
            let response = try await client.syncAudiobooks()
            if response.success {
                // A pull that finds nothing new stays quiet.
                let n = response.result?.synced ?? 0
                if n > 0 { syncMessage = "synced \(n) book\(n == 1 ? "" : "s")" }
            } else {
                syncMessage = "couldn't sync audiobooks"
            }
        } catch {
            syncMessage = "couldn't sync audiobooks: \(error.localizedDescription)"
        }
        // Reload either way, so a pull still refreshes the list when the sync itself fails.
        await loadTask?.value          // a load started before the sync can't see the new books
        await load(client: client)
    }

    /// A random book from the shown list for shuffle, preferring one not finished yet.
    func randomBook() -> Audiobook? {
        let unfinished = filteredAndSorted.filter { $0.progress?.isFinished != true }
        return (unfinished.isEmpty ? filteredAndSorted : unfinished).randomElement()
    }

    /// Client-side filter over the full library (GET /audiobooks returns every book; paging and sorting are client-side).
    /// Title + author, case-insensitive; results title-sorted.
    func setSearchText(_ text: String) {
        searchText = text
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            searchResults = []
            return
        }
        searchResults = books
            .filter { $0.title.lowercased().contains(q) || $0.author.lowercased().contains(q) }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }
}
