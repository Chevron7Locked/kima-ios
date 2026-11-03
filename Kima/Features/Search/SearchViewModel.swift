import SwiftUI
import os

private let soulseekLog = Logger(subsystem: "com.chevron7locked.kima", category: "Soulseek")

// MARK: - ViewModel

/// Search tab state machine, owned by `SearchView`. Library and discover searches fire together: library results
/// show first, discover ~100–500 ms later, then similar artists if discover found a top music artist.
/// Cancelling `searchTask` propagates into URLSession.
@Observable
@MainActor
final class SearchViewModel {

    // MARK: Inputs

    var query:        String       = ""
    var activeFilter: SearchFilter = .all

    // MARK: Results

    private(set) var libraryResults:  SearchResults?
    /// Mixed-type external results from /search/discover?type=all.
    private(set) var discoverResults: [DiscoverResult] = []
    /// Similar artists from /search/discover/similar — fires after discover resolves.
    private(set) var similarArtists:  [DiscoverResult] = []
    /// Last.fm alias correction (e.g. alternate spelling → canonical name + mbid).
    private(set) var aliasInfo:       AliasInfo?

    // MARK: Loading flags

    private(set) var isLibraryLoading:  Bool = false
    private(set) var isDiscoverLoading: Bool = false
    private(set) var isSimilarLoading:  Bool = false
    private(set) var hasSearched:       Bool = false
    /// Both library and discover requests failed (offline / server down).
    private(set) var searchFailed:      Bool = false

    /// True while any fetch is in flight.
    var isLoading: Bool { isLibraryLoading || isDiscoverLoading || isSimilarLoading }

    /// True when at least one bucket that can render is non-empty: the discover top match (a `.music` artist),
    /// related artists, and the library buckets. Unrendered discover tracks/podcasts must not count, or the
    /// empty state would be suppressed and the screen left blank.
    var hasAnyResults: Bool {
        discoverResults.contains { $0.type == .music }
        || !similarArtists.isEmpty
        || !(libraryResults?.artists.isEmpty    ?? true)
        || !(libraryResults?.albums.isEmpty     ?? true)
        || !(libraryResults?.tracks.isEmpty     ?? true)
        || !(libraryResults?.podcasts.isEmpty   ?? true)
        || !(libraryResults?.audiobooks.isEmpty ?? true)
        || !(libraryResults?.episodes.isEmpty   ?? true)
    }

    // MARK: Soulseek (P2P) state
    //
    // Separate pipeline: own feature gate, longer debounce, and a poll loop (`onSoulseekQueryChange`).

    /// GET /soulseek/status result — false when the server has no Soulseek credentials
    /// configured. Gates the Soulseek filter chip (`SearchView.filterChips`) and idle-prompt
    /// entry row (`SearchIdlePrompt.soulseekEnabled`).
    private(set) var soulseekEnabled: Bool = false
    /// Results for the current soulseek search (each poll replaces them with the full snapshot).
    private(set) var soulseekResults: [SoulseekResult] = []
    private(set) var isSoulseekSearching: Bool = false
    /// Result ids (`SoulseekResult.id`) with an in-flight download POST — drives the per-row
    /// spinner in `SoulseekResultsView`.
    private(set) var downloadingKeys: Set<String> = []

    // MARK: Private state

    private var searchTask: Task<Void, Never>?
    private var soulseekTask: Task<Void, Never>?
    /// Query last fetched by `performSearch`; lets `onFilterChange` catch up after soulseek-scope edits.
    private var lastLibraryQuery: String = ""
    private var searchGeneration = 0
    /// Soulseek download keys with a POST still running; unlike `downloadingKeys` the 5 s spinner ceiling doesn't clear it.
    private var inFlightDownloads: Set<String> = []

    // MARK: Public interface

    /// GET /soulseek/status on load — best-effort. Any failure (network error, or an older
    /// server without the route deployed) leaves `soulseekEnabled` false and the scope stays
    /// hidden, which is the correct fallback.
    func loadSoulseekStatus(client: KimaAPIClient) async {
        guard let status = try? await client.getSoulseekStatus() else { return }
        soulseekEnabled = status.enabled
    }

    /// Call on every query character change. Routes to the Soulseek search+poll flow when
    /// that's the active scope; otherwise debounces 350 ms and ignores queries < 2 chars
    /// (unchanged library/discover behavior).
    func onQueryChange(client: KimaAPIClient) {
        if activeFilter == .soulseek {
            onSoulseekQueryChange(client: client)
            return
        }
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            if q.isEmpty { reset() }
            return
        }
        searchTask = Task { [weak self, q] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            await self.performSearch(query: q, client: client)
        }
    }

    /// Call when `activeFilter` changes. All/Library/Discover share one fetch, so switching among
    /// them needs no request. Switching INTO Soulseek starts a fresh search+poll; OUT cancels it.
    func onFilterChange(client: KimaAPIClient) {
        if activeFilter == .soulseek {
            onSoulseekQueryChange(client: client)
            return
        }
        soulseekTask?.cancel()
        isSoulseekSearching = false

        // Edits made in the Soulseek scope never reached library/discover; catch up now.
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, q != lastLibraryQuery else { return }
        searchTask?.cancel()
        searchTask = Task { [weak self, q] in
            await self?.performSearch(query: q, client: client)
        }
    }

    /// Resets to idle state (called when the search field is fully cleared).
    func reset() {
        searchTask?.cancel()
        soulseekTask?.cancel()
        searchGeneration &+= 1
        searchFailed      = false
        libraryResults    = nil
        discoverResults   = []
        similarArtists    = []
        aliasInfo         = nil
        hasSearched       = false
        isLibraryLoading  = false
        isDiscoverLoading = false
        isSimilarLoading  = false
        soulseekResults      = []
        isSoulseekSearching  = false
    }

    /// Cancels both in-flight pipelines (called on tab disappear so the ~14 s soulseek poll stops).
    func cancelInFlight() {
        searchTask?.cancel()
        soulseekTask?.cancel()
    }

    // MARK: Fetch

    /// Internal (not private) so unit tests can call it without the debounce.
    func performSearch(query: String, client: KimaAPIClient) async {
        searchGeneration &+= 1
        let gen = searchGeneration
        searchFailed      = false
        lastLibraryQuery  = query
        hasSearched       = true
        isLibraryLoading  = true
        isDiscoverLoading = true
        libraryResults    = nil
        discoverResults   = []
        similarArtists    = []
        aliasInfo         = nil

        // Library + discover start concurrently.
        async let libFetch  = client.searchLibrary(query: query)
        async let discFetch = client.searchDiscoverAll(query: query)

        // Library: local DB — surfaces first.
        var libFailed = false
        let lib: SearchResults?
        do { lib = try await libFetch } catch { lib = nil; libFailed = true }
        guard gen == searchGeneration else { return }  // a newer search owns the state
        if Task.isCancelled { isLibraryLoading = false; isDiscoverLoading = false; return }
        libraryResults   = lib
        isLibraryLoading = false

        // Discover: external (Last.fm / iTunes / Deezer) — arrives ~100–500 ms later.
        var discFailed = false
        let discResp: DiscoverAllResponse?
        do { discResp = try await discFetch } catch { discResp = nil; discFailed = true }
        guard gen == searchGeneration else { return }
        if Task.isCancelled { isDiscoverLoading = false; return }
        discoverResults   = discResp?.results  ?? []
        aliasInfo         = discResp?.aliasInfo
        isDiscoverLoading = false
        searchFailed      = libFailed && discFailed

        // Similar artists: fires only if discover found a top music artist.
        if let top = discoverResults.first(where: { $0.type == .music }) {
            isSimilarLoading = true
            let similar = (try? await client.searchDiscoverSimilar(
                artist: top.name,
                mbid:   top.mbid ?? ""
            )) ?? []
            guard gen == searchGeneration else { return }
            similarArtists   = similar
            isSimilarLoading = false
        }
    }

    /// Re-runs the last library/discover search (the "try again" button on the error state).
    func retrySearch(client: KimaAPIClient) {
        searchTask?.cancel()
        let q = lastLibraryQuery
        searchTask = Task { [weak self] in await self?.performSearch(query: q, client: client) }
    }

    // MARK: Soulseek fetch

    /// Debounced (800 ms; the server rate-limits P2P searches) entry point for the Soulseek scope.
    /// Cancels any in-flight soulseek search+poll first.
    private func onSoulseekQueryChange(client: KimaAPIClient) {
        soulseekTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            if q.isEmpty {
                reset()
            }
            return
        }
        soulseekTask = Task { [weak self, q] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            await self.performSoulseekSearch(query: q, client: client)
        }
    }

    /// Fires the P2P search, then polls for ~14 s. Each poll returns the server's full snapshot
    /// for this `searchId`, so replacing `soulseekResults` each time needs no merge.
    private func performSoulseekSearch(query: String, client: KimaAPIClient) async {
        hasSearched          = true
        isSoulseekSearching  = true
        soulseekResults      = []
        defer { isSoulseekSearching = false }

        guard let searchId = try? await client.searchSoulseek(query: query) else {
            return
        }
        guard !Task.isCancelled else { return }

        let pollInterval: UInt64 = 1_000_000_000  // 1s
        let maxPolls = 14                         // ~14s total poll window

        for _ in 0..<maxPolls {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: pollInterval)
            guard !Task.isCancelled else { return }
            do {
                soulseekResults = try await client.getSoulseekSearchResults(searchId: searchId)
            } catch APIError.http(status: 404, _) {
                // Server evicted the search session — stop polling but keep the
                // last-known-good results on screen instead of wiping them.
                break
            } catch {
                // Transient error — keep last-known-good results, retry next poll.
            }
        }
    }

    /// Fires a Soulseek download. Marks the row "downloading" at once and clears it when the POST
    /// returns or after a 5 s ceiling (the POST can block ~120 s server-side). Success shows up in
    /// the Downloads/Activity feed; a client-side failure never creates a job, so it is toasted here.
    func downloadSoulseek(_ result: SoulseekResult, client: KimaAPIClient, toast: ToastCenter) {
        let key = result.id
        guard !inFlightDownloads.contains(key) else { return }
        inFlightDownloads.insert(key)
        downloadingKeys.insert(key)

        Task { [weak self] in
            do {
                try await client.downloadFromSoulseek(
                    username: result.username,
                    filepath: result.path,
                    filename: result.filename,
                    size:     result.size,
                    artist:   result.parsedArtist,
                    album:    result.parsedAlbum,
                    title:    result.parsedTitle
                )
            } catch {
                soulseekLog.error("Soulseek download failed: \(error.localizedDescription, privacy: .public)")
                toast.show(AcquirePermission.failureMessage(error, fallback: "couldn't start download — try again."),
                           style: .error)
            }
            self?.downloadingKeys.remove(key)
            self?.inFlightDownloads.remove(key)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.downloadingKeys.remove(key)
        }
    }
}
