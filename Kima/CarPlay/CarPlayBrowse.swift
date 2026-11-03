import CarPlay
import UIKit

// MARK: - CarPlayBrowse
//
// Builds the CarPlay root list: NOW PLAYING (omitted when idle), LIBRARY, and CONTINUE. Rows push a screen rather
// than play. CONTINUE's fetch is a root-level task that the scene delegate cancels on every rebuild/disconnect.

@MainActor
enum CarPlayBrowse {

    // MARK: - Auth gate

    /// Shown when `CarPlayLink.shared.environment` is nil — no server connected yet, or the
    /// phone session signed out. Uses `CPListTemplate`'s built-in empty-view (title + subtitle)
    /// rather than a fake tappable row: there's nothing to select here.
    static func buildAuthGateTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "kima", sections: [])
        template.emptyViewTitleVariants = ["open kima on your iPhone"]
        template.emptyViewSubtitleVariants = ["sign in there to connect your library to the car."]
        return template
    }

    // MARK: - Root

    /// Builds the home list template and returns it plus the CONTINUE-section load `Task`, so
    /// the caller can cancel it on the next rebuild. NOW PLAYING and LIBRARY are both static (no
    /// fetch) and are applied to the template immediately, before this function even returns —
    /// only CONTINUE needs the background task.
    static func buildRoot(
        env: AppEnvironment, interfaceController: CPInterfaceController
    ) -> (root: CPListTemplate, tasks: [Task<Void, Never>]) {
        let template = CPListTemplate(title: "kima", sections: [])
        template.trailingNavigationBarButtons = [nowPlayingBarButton(interfaceController: interfaceController)]

        let nowPlaying = nowPlayingSection(env: env, interfaceController: interfaceController)
        let librarySection = CPListSection(
            items: libraryRows(env: env, interfaceController: interfaceController),
            header: "library", sectionIndexTitle: nil
        )
        // Paint NOW PLAYING + LIBRARY on the very first frame — neither needs a network round
        // trip, so there is no reason to gate them behind CONTINUE's fetch the way BROWSE used
        // to be gated. CONTINUE simply isn't in this initial section list yet.
        template.updateSections([nowPlaying, librarySection].compactMap { $0 })

        let task = Task { @MainActor in
            var continueSection: CPListSection?
            do {
                let items = try await env.client.getContinueListeningAudiobooks()
                guard !Task.isCancelled else { return }
                if !items.isEmpty {
                    let shelf = await continueShelf(for: items, env: env, interfaceController: interfaceController)
                    guard !Task.isCancelled else { return }
                    var sectionItems: [CPListTemplateItem] = [shelf]
                    let shelfCap = Int(CPMaximumNumberOfGridImages)
                    if items.count > shelfCap {
                        sectionItems.append(moreNoticeItem(remaining: items.count - shelfCap))
                    }
                    continueSection = CPListSection(items: sectionItems, header: "continue listening", sectionIndexTitle: nil)
                }
            } catch {
                guard !Task.isCancelled else { return }
                // NOW PLAYING / LIBRARY still work; CONTINUE says it failed instead of vanishing.
                let failed = CPListItem(text: "couldn't load continue listening",
                                        detailText: "check your connection and try again.")
                failed.isEnabled = false
                continueSection = CPListSection(items: [failed], header: "continue listening", sectionIndexTitle: nil)
            }
            template.updateSections([nowPlaying, librarySection, continueSection].compactMap { $0 })
        }
        return (template, [task])
    }

    // MARK: - LIBRARY rows

    private static func libraryRows(
        env: AppEnvironment, interfaceController: CPInterfaceController
    ) -> [CPListItem] {
        let search = CPListItem(text: "search", detailText: nil, image: UIImage(systemName: "magnifyingglass"))
        search.accessoryType = .disclosureIndicator
        search.handler = { _, completion in
            CarPlaySearchCoordinator.present(env: env, interfaceController: interfaceController)
            completion()
        }

        let artists = CPListItem(text: "artists", detailText: nil, image: UIImage(systemName: "music.mic"))
        artists.accessoryType = .disclosureIndicator
        artists.handler = { _, completion in
            CarPlayBrowse.pushArtistsList(env: env, interfaceController: interfaceController)
            completion()
        }

        let albums = CPListItem(text: "albums", detailText: nil, image: UIImage(systemName: "square.stack"))
        albums.accessoryType = .disclosureIndicator
        albums.handler = { _, completion in
            CarPlayBrowse.pushAlbumsList(env: env, interfaceController: interfaceController)
            completion()
        }

        let audiobooks = CPListItem(text: "audiobooks", detailText: nil, image: UIImage(systemName: "books.vertical"))
        audiobooks.accessoryType = .disclosureIndicator
        audiobooks.handler = { _, completion in
            CarPlayBrowse.pushAudiobooksLibrary(env: env, interfaceController: interfaceController)
            completion()
        }

        let podcasts = CPListItem(text: "podcasts", detailText: nil, image: UIImage(systemName: "mic"))
        podcasts.accessoryType = .disclosureIndicator
        podcasts.handler = { _, completion in
            CarPlayBrowse.pushPodcastsList(env: env, interfaceController: interfaceController)
            completion()
        }

        let playlists = CPListItem(text: "playlists", detailText: nil, image: UIImage(systemName: "music.note.list"))
        playlists.accessoryType = .disclosureIndicator
        playlists.handler = { _, completion in
            CarPlayBrowse.pushPlaylistsList(env: env, interfaceController: interfaceController)
            completion()
        }

        return [search, artists, albums, audiobooks, podcasts, playlists]
    }

    // MARK: - CONTINUE shelf

    /// One cover shelf of in-progress books. Tap pushes the book-detail screen (NOT instant-play)
    /// — the redesign's "deliberate, not a jukebox" direction. `item.currentTime` is already
    /// known here, so it's passed straight through as `knownCurrentTime`, skipping the
    /// fetched-progress-can-come-back-nil footgun documented on `CarPlayPlayback.playAudiobook`.
    private static func continueShelf(
        for items: [AudiobookContinueItem], env: AppEnvironment, interfaceController: CPInterfaceController
    ) async -> CPListImageRowItem {
        let entries = items.map { item in
            CarPlayCoverShelf.Entry(title: item.title, coverId: item.coverUrl) {
                CarPlayBrowse.pushBookDetail(
                    bookId: item.id, title: item.title, knownCurrentTime: item.currentTime,
                    env: env, interfaceController: interfaceController
                )
            }
        }
        return await CarPlayCoverShelf.buildShelf(entries: entries, env: env, interfaceController: interfaceController)
    }
}
