import CarPlay
import UIKit

// MARK: - CarPlayAudiobookDetail
//
// Book detail. Re-fetches the full `Audiobook` via `getAudiobook(id:)` because list responses don't reliably carry
// `sections` (chapters). Start Over (`restartAudiobook` at 0) must force-reload even if the book is already playing.

extension CarPlayBrowse {

    static func pushBookDetail(
        bookId: String, title: String, knownCurrentTime: Double?,
        env: AppEnvironment, interfaceController: CPInterfaceController
    ) {
        let template = pushLoadingCarPlayList(title: title, on: interfaceController)

        Task { @MainActor in
            guard let book = try? await env.client.getAudiobook(id: bookId) else {
                setCarPlayListLoadFailed(template)
                return
            }
            // `knownCurrentTime` (from a CONTINUE row) wins over the freshly-fetched progress —
            // mirrors the same footgun documented on CarPlayPlayback.playAudiobook: a fetch that
            // comes back with `progress == nil` must never be read as "start over."
            let resumeTime = knownCurrentTime ?? book.progress?.currentTime ?? 0

            var sections: [CPListSection] = [
                CPListSection(
                    items: [
                        resumeRow(for: book, resumeTime: resumeTime, env: env, interfaceController: interfaceController),
                        startOverRow(for: book, env: env, interfaceController: interfaceController),
                    ],
                    header: nil, sectionIndexTitle: nil
                )
            ]
            if let chapters = book.sections, !chapters.isEmpty {
                let capped = clampedForCarPlay(chapters)
                var rows = capped.map { chapterRow(for: $0, book: book, env: env, interfaceController: interfaceController) }
                if capped.count < chapters.count { rows.append(moreNoticeItem(remaining: chapters.count - capped.count)) }
                sections.append(CPListSection(items: rows, header: "chapters", sectionIndexTitle: nil))
            }

            if #available(iOS 18.4, *) { template.showsSpinnerWhileEmpty = false }
            template.updateSections(sections)
        }
    }

    // MARK: - Rows

    private static func resumeRow(
        for book: Audiobook, resumeTime: Double, env: AppEnvironment, interfaceController: CPInterfaceController
    ) -> CPListItem {
        let remaining = max(0, book.duration - resumeTime)
        let row = CPListItem(
            text: "resume", detailText: "\(carPlayTimeText(seconds: remaining)) left",
            image: UIImage(systemName: "play.circle")
        )
        row.handler = { _, completion in
            Task { @MainActor in
                if await CarPlayPlayback.playAudiobook(id: book.id, resumeAt: resumeTime, env: env) {
                    pushNowPlaying(on: interfaceController)
                } else {
                    presentCarPlayError("couldn't load this book", on: interfaceController)
                }
                completion()
            }
        }
        return row
    }

    private static func startOverRow(
        for book: Audiobook, env: AppEnvironment, interfaceController: CPInterfaceController
    ) -> CPListItem {
        let row = CPListItem(
            text: "start over", detailText: "play from the beginning",
            image: UIImage(systemName: "gobackward")
        )
        row.handler = { _, completion in
            Task { @MainActor in
                if await CarPlayPlayback.restartAudiobook(id: book.id, env: env) {
                    pushNowPlaying(on: interfaceController)
                } else {
                    presentCarPlayError("couldn't load this book", on: interfaceController)
                }
                completion()
            }
        }
        return row
    }

    private static func chapterRow(
        for chapter: AudiobookSection, book: Audiobook,
        env: AppEnvironment, interfaceController: CPInterfaceController
    ) -> CPListItem {
        let row = CPListItem(text: chapter.title, detailText: carPlayTimeText(seconds: chapter.start))
        row.handler = { _, completion in
            Task { @MainActor in
                if await CarPlayPlayback.restartAudiobook(id: book.id, at: chapter.start, env: env) {
                    pushNowPlaying(on: interfaceController)
                } else {
                    presentCarPlayError("couldn't load this book", on: interfaceController)
                }
                completion()
            }
        }
        return row
    }
}
