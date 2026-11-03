import Foundation
import Observation

// MARK: - CollectionViewModel

/// Paginated Collection screen view model.
/// Owns filter / sort / pagination state; loads only the active tab's query.
@MainActor
@Observable
final class CollectionViewModel {

    // MARK: Tab / filter / sort / pagination / search

    var activeTab: CollectionTab = .artists
    var filter: LibraryFilter = .owned
    var sortBy: LibrarySortOption = .name
    var itemsPerPage: Int = 40
    var currentPage: Int = 1
    /// Live search text. Artists: server-side (ILIKE). Albums/tracks: client-side on loaded page.
    var searchText: String = ""
    private var loadTask: Task<Void, Never>?

    // MARK: Data phases

    var artistsPhase: LoadPhase<[Artist]> = .loading
    var albumsPhase: LoadPhase<[Album]> = .loading
    var tracksPhase: LoadPhase<[Track]> = .loading

    /// The filter and sort each tab's shown results were loaded with. A tab whose results came
    /// from a different filter or sort shows the loading state instead of the old results.
    private struct ResultsKey: Equatable { let filter: LibraryFilter; let sort: LibrarySortOption }
    @ObservationIgnored private var loadedKeys: [CollectionTab: ResultsKey] = [:]
    private var currentKey: ResultsKey { ResultsKey(filter: filter, sort: sortBy) }

    /// True when `tab` has results on screen that match the current filter and sort.
    private func showsCurrentResults(_ tab: CollectionTab, loaded: Bool) -> Bool {
        loaded && loadedKeys[tab] == currentKey
    }

    // MARK: Totals (drives pagination)

    var artistsTotal: Int = 0
    var albumsTotal: Int = 0
    var tracksTotal: Int = 0

    // MARK: Shuffle

    var isShuffling: Bool = false

    // MARK: Sort cache

    /// Cached result of the last `sortedArtists` computation. `@ObservationIgnored` keeps
    /// SwiftUI from tracking this field — observation triggers come from `artistsPhase` and
    /// `sortBy` instead, which cause body re-eval and a new cache-key check.
    @ObservationIgnored private var _sortedArtistsCache: [Artist] = []
    /// Key under which `_sortedArtistsCache` was built: "\(sortBy)|\(count)|\(firstId)|\(lastId)".
    @ObservationIgnored private var _sortedArtistsCacheKey: String = ""

    // MARK: Computed

    var activeTotal: Int {
        switch activeTab {
        case .artists: return artistsTotal
        case .albums:  return albumsTotal
        case .tracks:  return tracksTotal
        }
    }

    var totalPages: Int {
        guard activeTotal > 0, itemsPerPage > 0 else { return 1 }
        return (activeTotal + itemsPerPage - 1) / itemsPerPage
    }

    /// Artists sorted client-side for name/name-desc.
    /// Cached by (sortBy + all ids) so the O(n log n) sort and per-element regex run once per loaded page,
    /// not on every body evaluation. A change to `artistsPhase` or `sortBy` yields a new key and invalidates it.
    var sortedArtists: [Artist] {
        guard case .loaded(let list) = artistsPhase else { return [] }
        guard sortBy == .name || sortBy == .nameDesc else { return list }
        // Complete key over every id — a same-count set swap (add/remove different artists that
        // leave count + first/last unchanged) must still invalidate. Name is a stable sort field,
        // so the id set fully captures what the sort depends on.
        let key = "\(sortBy.rawValue)|" + list.map(\.id).joined(separator: ",")
        if !_sortedArtistsCache.isEmpty && _sortedArtistsCacheKey == key {
            return _sortedArtistsCache
        }
        let sorted = Self.sortedByName(list, descending: sortBy == .nameDesc)
        _sortedArtistsCache = sorted
        _sortedArtistsCacheKey = key
        return sorted
    }

    /// The phone's artist name order ("The Beatles" files under B). CarPlay's artist list uses it too.
    static func sortedByName(_ list: [Artist], descending: Bool = false) -> [Artist] {
        list.sorted { a, b in
            let primary = artistSortKey(a.effectiveName).localizedCompare(artistSortKey(b.effectiveName))
            if primary != .orderedSame {
                return descending ? primary == .orderedDescending : primary == .orderedAscending
            }
            let secondary = a.effectiveName.localizedCompare(b.effectiveName)
            return descending ? secondary == .orderedDescending : secondary == .orderedAscending
        }
    }

    private static func artistSortKey(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespaces)
        let stripped = t.replacingOccurrences(of: "^[Tt]he\\s+", with: "",
                                               options: .regularExpression)
        return stripped.isEmpty ? t : stripped
    }

    // MARK: Private helpers

    private var offset: Int { (currentPage - 1) * itemsPerPage }

    /// Cancel-before-replace load dispatch, the single entry point for starting an active-tab load. It cancels any
    /// in-flight load/search task first, so a slower earlier response cannot overwrite a newer selection.
    // Internal so the view's initial-load `.task` uses the same path: a bare `.task { loadActiveTab() }` is not
    // stored in `loadTask`, so a later kickLoad could not cancel it.
    func kickLoad(debounce: Duration? = nil, resetPage: Bool = false, using client: KimaAPIClient) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            if let d = debounce { try? await Task.sleep(for: d) }
            guard !Task.isCancelled, let self else { return }
            if resetPage { self.currentPage = 1 }
            await self.loadActiveTab(using: client)
        }
    }

    // MARK: Load actions

    func loadActiveTab(using client: KimaAPIClient) async {
        switch activeTab {
        case .artists: await loadArtists(using: client)
        case .albums:  await loadAlbums(using: client)
        case .tracks:  await loadTracks(using: client)
        }
    }

    func loadArtists(using client: KimaAPIClient) async {
        // Blank to the skeleton unless the shown results already match this filter and sort. A
        // re-fetch of the same query — a real refresh or a SPURIOUS re-trigger (a parent re-render
        // re-running the load `.task`) — keeps them on screen until the new page arrives.
        let key = currentKey
        if !showsCurrentResults(.artists, loaded: artistsPhase.isLoaded) { artistsPhase = .loading }
        do {
            let q = searchText.isEmpty ? nil : searchText
            let resp = try await client.getLibraryArtists(
                filter: filter.rawValue, sortBy: sortBy.rawValue,
                limit: itemsPerPage, offset: offset, query: q)
            guard !Task.isCancelled else { return }
            artistsTotal = resp.total ?? 0
            // Invalidate the sortedArtists cache on every fresh page: content can change while
            // count/first/last id stay equal (e.g. an interior metadata edit), so the cheap key
            // alone could serve stale results. Resetting forces a re-sort on next access.
            _sortedArtistsCache = []
            _sortedArtistsCacheKey = ""
            artistsPhase = .loaded(resp.artists)
            loadedKeys[.artists] = key
        } catch {
            guard !Task.isCancelled else { return }
            artistsPhase = .failed(error.localizedDescription)
        }
    }

    func loadAlbums(using client: KimaAPIClient) async {
        // Skeleton unless the shown grid matches this filter and sort (see loadArtists).
        let key = currentKey
        if !showsCurrentResults(.albums, loaded: albumsPhase.isLoaded) { albumsPhase = .loading }
        do {
            let resp = try await client.getLibraryAlbums(
                filter: filter.rawValue, sortBy: sortBy.rawValue,
                limit: itemsPerPage, offset: offset)
            guard !Task.isCancelled else { return }
            albumsTotal = resp.total ?? 0
            // Albums: no server-side query param — filter loaded page client-side.
            let all = resp.albums
            let albums = clientFilter(all, query: searchText) { [$0.effectiveTitle, $0.artist?.name] }
            albumsPhase = .loaded(albums)
            loadedKeys[.albums] = key
        } catch {
            guard !Task.isCancelled else { return }
            albumsPhase = .failed(error.localizedDescription)
        }
    }

    func loadTracks(using client: KimaAPIClient) async {
        // Skeleton unless the shown list matches this filter and sort (see loadArtists).
        let key = currentKey
        if !showsCurrentResults(.tracks, loaded: tracksPhase.isLoaded) { tracksPhase = .loading }
        do {
            let resp = try await client.getLibraryTracks(
                sortBy: sortBy.rawValue,
                limit: itemsPerPage, offset: offset)
            guard !Task.isCancelled else { return }
            tracksTotal = resp.total ?? 0
            // Tracks: no server-side query param — filter loaded page client-side.
            let all = resp.tracks
            let tracks = clientFilter(all, query: searchText) { [$0.effectiveTitle, $0.artist?.name] }
            tracksPhase = .loaded(tracks)
            loadedKeys[.tracks] = key
        } catch {
            guard !Task.isCancelled else { return }
            tracksPhase = .failed(error.localizedDescription)
        }
    }

    /// Case-insensitive substring filter applied to a list of items.
    /// `fields` is a closure that extracts the searchable string fields from each item.
    private func clientFilter<T>(
        _ items: [T],
        query: String,
        fields: (T) -> [String?]
    ) -> [T] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter { item in
            fields(item).compactMap { $0?.lowercased() }.contains { $0.contains(q) }
        }
    }

    // MARK: State transitions

    func selectTab(_ tab: CollectionTab, using client: KimaAPIClient) {
        guard tab != activeTab else { return }
        activeTab = tab
        if !sortBy.available(for: tab) { sortBy = .name }
        searchText = ""         // clear search on tab change
        if tab == .tracks { filter = .owned }
        currentPage = 1
        kickLoad(using: client)
    }

    /// Debounced search: cancels the prior task, waits 300 ms, then reloads page 1.
    func setSearchText(_ text: String, using client: KimaAPIClient) {
        searchText = text
        kickLoad(debounce: .milliseconds(300), resetPage: true, using: client)
    }

    /// After any filter / sort / items-per-page change: reset page, reload.
    func applyRefinement(using client: KimaAPIClient) {
        currentPage = 1
        kickLoad(using: client)
    }

    func goToPage(_ page: Int, using client: KimaAPIClient) {
        let clamped = max(1, min(page, totalPages))
        guard clamped != currentPage else { return }
        currentPage = clamped
        kickLoad(using: client)
    }

    /// Refetch the active tab after a delete.
    func refetchActiveTab(using client: KimaAPIClient) {
        kickLoad(using: client)
    }

    // MARK: Shuffle library

    func shuffleLibrary(using client: KimaAPIClient, player: PlaybackController) async {
        guard !isShuffling else { return }
        isShuffling = true
        defer { isShuffling = false }
        do {
            let tracks = try await client.getShuffledTracks(limit: 500)
            guard !tracks.isEmpty else { return }
            player.play(tracks: tracks, startAt: 0, shuffle: false)
        } catch { /* silent: a failed shuffle leaves the queue as it was */ }
    }

    // MARK: Play from a card

    /// Every card whose play request is in flight, by card id: those cards show a spinner and
    /// ignore repeat taps. Grid rows carry no track lists, so a card play fetches the item's
    /// detail first (an artist's own albums and tracks, an album's own tracks) and answers
    /// seconds later — long enough that a tap with no feedback reads as a dead button.
    var startingIds: Set<String> = []
}

