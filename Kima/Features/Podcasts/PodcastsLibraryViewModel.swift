import Foundation
import Observation

// MARK: - PodcastSortOption

enum PodcastLibrarySortOption: String, CaseIterable {
    case title
    case author
    case latestEpisode = "latest episode"

    func sort(_ podcasts: [Podcast]) -> [Podcast] {
        switch self {
        case .title:  return podcasts.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .author: return podcasts.sorted { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
        // ISO-8601 strings sort by time; a show with no episodes goes last.
        case .latestEpisode: return podcasts.sorted { ($0.latestEpisodeAt ?? "") > ($1.latestEpisodeAt ?? "") }
        }
    }
}

// MARK: - Category rows

/// One category row below "top shows": its chart loads only when the row nears the screen.
enum PodcastCategoryRowPhase: Equatable {
    case idle, loading, failed
    case loaded([String])   // show ids, in chart order
}

// MARK: - PodcastsLibraryViewModel

/// The podcasts page: what you are listening to (from the server's listening list), your shows, rows picked from
/// the categories of the shows you follow, Apple's top shows, and a few category rows; the rest of the categories
/// sit behind one "categories" list.
@MainActor
@Observable
final class PodcastsLibraryViewModel {
    /// How many category rows the page shows before the "categories" list.
    static let categoryRowCount = 4
    /// The categories the page prefers for its rows, in order (Apple ids: comedy, society & culture, news,
    /// true crime, business, sports).
    static let preferredCategoryIds = [1303, 1324, 1489, 1488, 1321, 1545]
    static let newEpisodeLimit = 10

    private(set) var subscribed: [Podcast] = []
    private(set) var listening: PodcastListening?
    private(set) var forYou: [PodcastForYouRow] = []
    private(set) var topShows: [DiscoveryPodcast] = []
    /// Every top-level category, by name (the "categories" list).
    private(set) var categories: [PodcastCategory] = []
    private(set) var rowPhases: [Int: PodcastCategoryRowPhase] = [:]
    /// Bumped by a pull to refresh so rows already on screen load again.
    private(set) var rowGeneration = 0
    /// Shows loaded by any row, by id.
    @ObservationIgnored private var rowShows: [String: DiscoveryPodcast] = [:]
    private(set) var isLoading = false
    /// When the page last loaded, so coming back to the tab within a minute asks nothing again.
    @ObservationIgnored private var loadedAt: Date?

    var continueRows: [PodcastListeningRow] { listening?.inProgress ?? [] }
    var newRows: [PodcastListeningRow] { Array((listening?.newEpisodes ?? []).prefix(Self.newEpisodeLimit)) }

    /// The category rows on the page: not already a for-you row, preferred ones first, then by name,
    /// `categoryRowCount` of them.
    var rowCategories: [PodcastCategory] {
        let taken = Set(forYou.map(\.category.id))
        let open = categories.filter { !taken.contains($0.id) }
        let preferred = Self.preferredCategoryIds.compactMap { id in open.first { $0.id == id } }
        let rest = open.filter { !Self.preferredCategoryIds.contains($0.id) }
        return Array((preferred + rest).prefix(Self.categoryRowCount))
    }

    func shows(inRow id: Int) -> [DiscoveryPodcast] {
        guard case .loaded(let ids) = rowPhases[id] else { return [] }
        return ids.compactMap { rowShows[$0] }
    }

    // MARK: Sort cache

    @ObservationIgnored private var sortedCache: (key: String, shows: [Podcast])?

    func sortedSubscribed(sort: PodcastLibrarySortOption) -> [Podcast] {
        let key = "\(sort.rawValue)|" + subscribed.map { "\($0.id):\($0.latestEpisodeAt ?? "")" }.joined(separator: ",")
        if let sortedCache, sortedCache.key == key { return sortedCache.shows }
        let sorted = sort.sort(subscribed)
        sortedCache = (key, sorted)
        return sorted
    }

    func displayedSubscribed(sort: PodcastLibrarySortOption, pageSize: Int) -> [Podcast] {
        Array(sortedSubscribed(sort: sort).prefix(pageSize))
    }

    func hasMoreSubscribed(pageSize: Int) -> Bool { subscribed.count > pageSize }

    // MARK: - Load

    /// Everything above the category rows, fetched together. A part that fails keeps what it had, so one slow
    /// Apple answer never blanks the page. `force` (pull to refresh) also reloads the category rows.
    func load(client: KimaAPIClient, force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let loadedAt, Date.now.timeIntervalSince(loadedAt) < 60 { return }
        isLoading = true
        defer { isLoading = false }

        async let subs = try? client.getPodcasts()
        async let listen = try? client.getPodcastListening()
        async let rows = try? client.getPodcastsForYou()
        async let top = try? client.getPodcastChart(category: nil, limit: 24)
        async let tree = try? PodcastCategoryTree.load(client: client)

        if let s = await subs { subscribed = s }
        if let l = await listen { listening = l }
        if let r = await rows { forYou = r }
        if let t = await top { topShows = t }
        if let t = await tree {
            categories = t.filter { $0.parentId == nil }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        loadedAt = .now
        if force {
            rowPhases = [:]
            rowGeneration += 1
        }
    }

    /// The listening rails only — after an episode plays, so "continue" shows where it stopped.
    func reloadListening(client: KimaAPIClient) async {
        if let l = try? await client.getPodcastListening() { listening = l }
    }

    /// A category row's chart, asked for behind requests a person is waiting on. Runs once per row; a failed row
    /// asks again only when `retry` (its try-again button).
    func loadRow(_ id: Int, client: KimaAPIClient, retry: Bool = false) async {
        switch rowPhases[id] {
        case .loading, .loaded: return
        case .failed where !retry: return
        default: break
        }
        rowPhases[id] = .loading
        do {
            let shows = try await client.getPodcastChart(category: id, limit: 12, background: true)
            for show in shows { rowShows[show.id] = show }
            rowPhases[id] = .loaded(shows.map(\.id))
        } catch {
            rowPhases[id] = .failed
        }
    }

    // MARK: - Your shows

    /// Asks the server to check every subscribed feed for new episodes; the caller reloads afterwards.
    func refreshAll(client: KimaAPIClient) async throws {
        _ = try await client.refreshAllPodcasts()
    }

    func removeSubscribed(id: String) {
        subscribed.removeAll { $0.id == id }
    }

    /// Reload the shows and the listening rails after a follow, without the discovery rows.
    func refreshSubscribed(client: KimaAPIClient) async {
        if let s = try? await client.getPodcasts() { subscribed = s }
        await reloadListening(client: client)
    }

    /// The followed show for a listening row, or a stand-in carrying the row's own show fields.
    func podcast(for show: PodcastListeningShow) -> Podcast {
        subscribed.first { $0.id == show.id } ?? Podcast(
            id: show.id, title: show.title, author: "", description: nil, coverUrl: show.coverUrl,
            autoDownloadEpisodes: false, genres: nil, feedUrl: nil, episodes: [], episodeCount: nil,
            isSubscribed: true, episodeTotal: nil
        )
    }
}
