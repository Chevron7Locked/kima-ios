import CarPlay
import UIKit

// MARK: - CarPlayCoverShelf
// Fetches covers concurrently (placeholder on failure), then builds the `CPListImageRowItem` (images are set at init).
// Uses the deprecated `init(text:images:imageTitles:)`: the element-based init is iOS 26 only (target is iOS 18), so
// deprecation warnings are expected. `imageTitles` labels every cover; taps route by index via `listImageRowHandler`.

@MainActor
enum CarPlayCoverShelf {

    /// One cover in a shelf: display title + cover id for the fetch, plus the tap action for
    /// when its cover is selected. `onSelect` is explicitly `@MainActor` (not left to inference)
    /// so it can be built at any call site and invoked later from `listImageRowHandler` — which
    /// fires on CarPlay's template UI actor — without an extra Task hop.
    struct Entry {
        let title: String
        let coverId: String?
        let onSelect: @MainActor () -> Void
    }

    /// Fetches covers for `entries` (capped to `CPMaximumNumberOfGridImages`) concurrently and returns one
    /// `CPListImageRowItem` shelf. Failed fetches fall back to `CarPlayArtwork.placeholder`, so the image array always has
    /// one entry per cover: `listImageRowHandler`'s index must line up 1:1 with `entries`.
    static func buildShelf(
        entries: [Entry], env: AppEnvironment, interfaceController: CPInterfaceController
    ) async -> CPListImageRowItem {
        let capped = Array(entries.prefix(Int(CPMaximumNumberOfGridImages)))
        let size = CarPlayArtwork.shelfImageSize(for: interfaceController)
        let server = env.server
        let coverIds = capped.map { $0.coverId }
        // Read once here on the main actor: `CarPlayArtwork.placeholder` is MainActor-isolated, and reading it from a child
        // task is an error under Swift 6 mode. Capturing the resolved `UIImage` avoids the actor hop.
        let placeholder = CarPlayArtwork.placeholder

        let images: [UIImage]
        if coverIds.isEmpty {
            images = []
        } else {
            images = await withTaskGroup(of: (Int, UIImage).self) { group in
                for (index, coverId) in coverIds.enumerated() {
                    group.addTask {
                        guard let coverId, !coverId.isEmpty,
                              let image = await loadCarPlayArtwork(coverId: coverId, server: server, size: size)
                        else { return (index, placeholder) }
                        return (index, image)
                    }
                }
                var ordered = [UIImage](repeating: placeholder, count: coverIds.count)
                for await (index, image) in group { ordered[index] = image }
                return ordered
            }
        }

        let item = CPListImageRowItem(text: "", images: images, imageTitles: capped.map { $0.title })
        // No title row: a nil `text` hides it, while an empty one leaves a stray disclosure chevron
        // above the covers. The deprecated initializer needs a non-nil text, so it is cleared here.
        item.text = nil
        item.listImageRowHandler = { _, index, completion in
            defer { completion() }
            guard capped.indices.contains(index) else { return }
            capped[index].onSelect()
        }
        return item
    }

    /// Builds shelves from `allItems`, chunked by `CPMaximumNumberOfGridImages` and capped at `maxShelves`. Appends a
    /// trailing `moreNoticeItem` row when items were truncated. Ready for `setCarPlayListLoaded`/`updateSections`.
    static func buildShelves<Item>(
        maxShelves: Int, allItems: [Item],
        env: AppEnvironment, interfaceController: CPInterfaceController,
        entry: @MainActor (Item) -> Entry
    ) async -> [CPListTemplateItem] {
        let perShelf = max(1, Int(CPMaximumNumberOfGridImages))
        let capped = Array(allItems.prefix(maxShelves * perShelf))
        guard !capped.isEmpty else { return [] }

        var shelves: [CPListTemplateItem] = []
        var start = 0
        while start < capped.count {
            let end = min(start + perShelf, capped.count)
            let entries = capped[start..<end].map(entry)
            shelves.append(await buildShelf(entries: entries, env: env, interfaceController: interfaceController))
            start = end
        }
        if capped.count < allItems.count {
            shelves.append(moreNoticeItem(remaining: allItems.count - capped.count))
        }
        return shelves
    }
}
