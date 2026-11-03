import CarPlay
import UIKit

// MARK: - CarPlaySearchCoordinator
// Backs the LIBRARY -> Search row. `CPSearchTemplate.delegate` is weak, so the coordinator is a `static let shared`.
// Results are flat `CPListItem`s (audiobooks, podcasts, tracks; albums/artists would need a second push), each
// stashing a `SearchSelection` on `userInfo` so selection routes without re-querying.
@MainActor
final class CarPlaySearchCoordinator: NSObject, CPSearchTemplateDelegate {

    static let shared = CarPlaySearchCoordinator()
    private override init() { super.init() }

    /// Set immediately before presenting. Weak so a stale coordinator can never keep a
    /// signed-out session's `AppEnvironment` (or its scene's interface controller) alive
    /// between searches — mirrors the weak `interfaceController` on `CarPlayNowPlaying`.
    private weak var env: AppEnvironment?
    private weak var interfaceController: CPInterfaceController?

    static func present(env: AppEnvironment, interfaceController: CPInterfaceController) {
        shared.env = env
        shared.interfaceController = interfaceController
        let template = CPSearchTemplate()
        template.delegate = shared
        interfaceController.pushTemplate(template, animated: true) { _, _ in }
    }

    // MARK: - CPSearchTemplateDelegate
    //
    // The protocol is already main-actor isolated in the SDK (unlike `CPNowPlayingTemplateObserver`), so this
    // `@MainActor` class satisfies it. Search runs in its own `Task` because the delegate methods are synchronous.

    func searchTemplate(
        _ searchTemplate: CPSearchTemplate, updatedSearchText searchText: String,
        completionHandler: @escaping ([CPListItem]) -> Void
    ) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let env, let interfaceController else {
            completionHandler([])
            return
        }
        Task { @MainActor in
            guard let results = try? await env.client.searchLibrary(query: query, type: "all", limit: 20) else {
                completionHandler([])
                return
            }
            let rows = Self.rows(for: results, env: env, interfaceController: interfaceController)
            completionHandler(clampedForCarPlay(rows))
        }
    }

    func searchTemplate(
        _ searchTemplate: CPSearchTemplate, selectedResult item: CPListItem,
        completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let env, let interfaceController, let selection = item.userInfo as? SearchSelection else { return }
        switch selection {
        case .audiobook(let id, let title):
            CarPlayBrowse.pushBookDetail(
                bookId: id, title: title, knownCurrentTime: nil,
                env: env, interfaceController: interfaceController
            )
        case .podcast(let id, let title):
            CarPlayBrowse.pushPodcastEpisodes(podcastId: id, title: title, env: env, interfaceController: interfaceController)
        case .track(let track):
            env.player.play(tracks: [track])
            pushNowPlaying(on: interfaceController)
        }
    }

    // MARK: - Result mapping

    private static func rows(
        for results: SearchResults, env: AppEnvironment, interfaceController: CPInterfaceController
    ) -> [CPListItem] {
        var rows: [CPListItem] = []

        for book in results.audiobooks {
            let detail = "audiobook" + (book.author.map { " · \($0)" } ?? "")
            let row = CPListItem(text: book.title, detailText: detail, image: CarPlayArtwork.placeholder)
            row.accessoryType = .disclosureIndicator
            row.userInfo = SearchSelection.audiobook(id: book.id, title: book.title)
            attachArtwork(to: row, coverId: book.coverUrl, env: env, interfaceController: interfaceController)
            rows.append(row)
        }

        for podcast in results.podcasts {
            let detail = "podcast" + (podcast.author.map { " · \($0)" } ?? "")
            let row = CPListItem(text: podcast.title, detailText: detail, image: CarPlayArtwork.placeholder)
            row.accessoryType = .disclosureIndicator
            row.userInfo = SearchSelection.podcast(id: podcast.id, title: podcast.title)
            attachArtwork(to: row, coverId: podcast.imageUrl, env: env, interfaceController: interfaceController)
            rows.append(row)
        }

        for track in results.tracks {
            let row = CPListItem(text: track.effectiveTitle, detailText: track.artist?.name, image: CarPlayArtwork.placeholder)
            row.userInfo = SearchSelection.track(track)
            attachArtwork(to: row, coverId: track.album?.coverArt, env: env, interfaceController: interfaceController)
            rows.append(row)
        }

        return rows
    }
}

// MARK: - SearchSelection
//
// Stashed on each row's `userInfo` at build time so `selectedResult` routes without re-running the query.
// Not `Codable`: `CPListItem.userInfo` is a plain `Any?` bag and is never archived.
private enum SearchSelection {
    case audiobook(id: String, title: String)
    case podcast(id: String, title: String)
    case track(Track)
}
