import Foundation
import Observation

// MARK: - Category tree (shared)

/// Apple's podcast category tree, fetched once per app run and shared by the podcasts page and the chart pages.
/// A failed fetch is not kept, so the next caller asks again.
@MainActor
enum PodcastCategoryTree {
    private static var cached: [PodcastCategory]?

    static func load(client: KimaAPIClient) async throws -> [PodcastCategory] {
        if let cached { return cached }
        let tree = try await client.getPodcastCategories()
        cached = tree
        return tree
    }
}

// MARK: - PodcastChartViewModel

/// One category's Apple chart (nil = the overall chart), paged 48 at a time until a short page, plus the
/// category's family for the chips: its own sub-categories, or its siblings when it is one.
@MainActor
@Observable
final class PodcastChartViewModel {
    enum Phase: Equatable {
        case loading
        /// The id is not one of Apple's categories.
        case noSuchCategory
        /// Apple (or the server) could not be reached and nothing is shown yet.
        case unreachable
        case loaded
    }

    static let pageSize = 48

    private(set) var phase: Phase = .loading
    private(set) var shows: [DiscoveryPodcast] = []
    private(set) var hasMore = true
    private(set) var isLoadingMore = false
    /// The last page after the first failed; the grid offers to try again.
    private(set) var loadMoreFailed = false
    /// The category itself; nil for the overall chart or while loading.
    private(set) var category: PodcastCategory?
    /// "all <parent>" first, then the parent's sub-categories. Empty when the category has none.
    private(set) var family: [PodcastCategoryRef] = []

    private(set) var categoryId: Int?
    @ObservationIgnored private var tree: [PodcastCategory] = []
    /// The chart the page now loading belongs to.
    @ObservationIgnored private var loadingFor: Int?

    init(categoryId: Int?) {
        self.categoryId = categoryId
    }

    var title: String { category?.name.lowercased() ?? (categoryId == nil ? "top shows" : "") }

    func load(client: KimaAPIClient) async {
        phase = .loading
        if let categoryId {
            guard let tree = try? await PodcastCategoryTree.load(client: client) else {
                phase = .unreachable
                return
            }
            self.tree = tree
            guard let found = tree.first(where: { $0.id == categoryId }) else {
                phase = .noSuchCategory
                return
            }
            category = found
            family = Self.family(of: found, in: tree)
        }
        shows = []
        hasMore = true
        await loadMore(client: client)
        phase = shows.isEmpty && hasMore ? .unreachable : .loaded
    }

    /// Switches to another chart in the same family, keeping the title row and chips on screen while it loads.
    func select(_ id: Int, client: KimaAPIClient) async {
        guard id != categoryId, let found = tree.first(where: { $0.id == id }) else { return }
        categoryId = id
        category = found
        shows = []
        hasMore = true
        await loadMore(client: client)
    }

    /// The next page. A failed page sets `loadMoreFailed` and leaves `hasMore` on, so its try-again asks again.
    func loadMore(client: KimaAPIClient) async {
        let asked = categoryId
        // One page at a time per chart; a page still loading for the chart a chip left does not block this one.
        guard hasMore, !(isLoadingMore && loadingFor == asked) else { return }
        isLoadingMore = true
        loadingFor = asked
        loadMoreFailed = false
        defer {
            if loadingFor == asked {
                isLoadingMore = false
                loadingFor = nil
            }
        }
        do {
            let page = try await client.getPodcastChart(category: asked, limit: Self.pageSize, offset: shows.count)
            guard asked == categoryId else { return }   // a chip switched charts meanwhile
            let known = Set(shows.map(\.id))
            shows += page.filter { !known.contains($0.id) }
            hasMore = page.count == Self.pageSize
        } catch {
            if asked == categoryId { loadMoreFailed = true }
        }
    }

    /// The chips: the parent as "all <parent>", then its sub-categories.
    nonisolated static func family(of category: PodcastCategory, in tree: [PodcastCategory]) -> [PodcastCategoryRef] {
        let parentId = category.parentId ?? category.id
        guard let parent = tree.first(where: { $0.id == parentId }) else { return [] }
        let children = tree.filter { $0.parentId == parentId }
        guard !children.isEmpty else { return [] }
        return [PodcastCategoryRef(id: parent.id, name: "all \(parent.name)")]
            + children.map { PodcastCategoryRef(id: $0.id, name: $0.name) }
    }
}
