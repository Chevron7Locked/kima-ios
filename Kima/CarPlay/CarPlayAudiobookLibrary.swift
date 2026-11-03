import CarPlay
import UIKit

// MARK: - CarPlayAudiobookLibrary
//
// The full Audiobooks list, pushed from the home screen's LIBRARY row: a wall of `CPListImageRowItem` shelves
// (see CarPlayCoverShelf.swift). Tapping a cover opens book detail and never plays instantly.

extension CarPlayBrowse {

    /// Pushed as a detail screen (not a root tab), so its load `Task` is self-contained and NOT
    /// tracked/cancelled by the scene delegate — same pattern as `pushPodcastEpisodes` /
    /// `pushPlaylistTracks` in CarPlayBrowseDetail.swift.
    static func pushAudiobooksLibrary(env: AppEnvironment, interfaceController: CPInterfaceController) {
        let template = pushLoadingCarPlayList(title: "audiobooks", on: interfaceController)

        Task { @MainActor in
            do {
                let result = try await env.client.getAudiobooks()
                let books: [Audiobook]
                switch result {
                case .configured(let list): books = list
                case .notConfigured: books = []
                }
                guard !books.isEmpty else {
                    setCarPlayListEmpty(
                        template, title: "audiobooks aren't set up",
                        subtitle: "set up Audiobookshelf in kima's web settings."
                    )
                    return
                }
                // Chunked into shelves of up to `CPMaximumNumberOfGridImages` covers each, capped
                // at 5 shelves total — plenty for a glanceable "wall of covers" without an
                // unbounded fetch; anything beyond that gets the trailing "see it on your phone"
                // notice `buildShelves` appends automatically.
                let shelves = await CarPlayCoverShelf.buildShelves(
                    maxShelves: 5, allItems: books, env: env, interfaceController: interfaceController
                ) { book in
                    CarPlayCoverShelf.Entry(title: book.title, coverId: book.coverUrl) {
                        // No continue-listening item here, so `knownCurrentTime` is nil — book
                        // detail falls back to the fetched `book.progress?.currentTime`.
                        CarPlayBrowse.pushBookDetail(
                            bookId: book.id, title: book.title, knownCurrentTime: nil,
                            env: env, interfaceController: interfaceController
                        )
                    }
                }
                setCarPlayListLoaded(template, rows: shelves)
            } catch {
                setCarPlayListLoadFailed(template)
            }
        }
    }
}
