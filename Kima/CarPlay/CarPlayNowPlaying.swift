import CarPlay
import MediaPlayer
import Observation
import UIKit

// MARK: - CarPlayNowPlaying
// Adds audiobook-only chrome (speed button, "Chapters") to the shared `CPNowPlayingTemplate`. It only mutates
// `.shared` (embedding the template in a tab/list crashes). `configure(env:)` is idempotent; `detach()` removes the
// single observer and is the teardown, since the singleton outlives this object and `deinit` never fires.
@MainActor
final class CarPlayNowPlaying: NSObject, CPNowPlayingTemplateObserver {

    static let shared = CarPlayNowPlaying()
    private override init() { super.init() }

    /// Captured at scene connect so the up-next observer can push the chapters list. Weak: the
    /// scene strongly retains it; we must not keep it alive past disconnect.
    private weak var interfaceController: CPInterfaceController?

    /// Guards the single `addObserver` on the singleton — adding twice = duplicate callbacks.
    private var isObserving = false

    /// Guards the `playbackType` observation loop so it's armed exactly once per attach.
    private var isObservingPlayback = false

    /// Chapter cache so re-fetching the book on every up-next tap is avoided. Invalidated when the
    /// currently-playing book changes (`cachedBookId` mismatch).
    private var cachedBookId: String?
    private var cachedSections: [AudiobookSection]?

    /// The app's canonical long-form rate ladder (mirrors `SpeedPickerButton.rates`). The speed
    /// button cycles these in order and wraps around.
    static let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    // MARK: - Scene lifecycle

    func attach(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    func detach() {
        if isObserving {
            CPNowPlayingTemplate.shared.remove(self)
            isObserving = false
        }
        isObservingPlayback = false   // stops the withObservationTracking re-arm loop
        interfaceController = nil
        cachedBookId = nil
        cachedSections = nil
    }

    // MARK: - Playback-state sync

    /// Bring the Now Playing chrome in line with whatever is playing RIGHT NOW, and keep it in sync
    /// as the item changes — including the common "started the book on the phone, then got in the
    /// car" case, where nothing is initiated through the CarPlay browse flow. Call from the scene
    /// delegate whenever the env is present (connect + sign-in). Idempotent.
    func activate(env: AppEnvironment) {
        configure(env: env)
        guard !isObservingPlayback else { return }
        isObservingPlayback = true
        observePlaybackType(env: env)
    }

    /// One-shot Observation tracking of `player.playbackType`; re-arms itself after each change so a
    /// phone-side switch (book → music → different book) re-runs `configure`, installing or stripping
    /// the audiobook chrome to match. Self-cancels once `isObservingPlayback` is cleared in `detach`.
    private func observePlaybackType(env: AppEnvironment) {
        withObservationTracking {
            _ = env.player.playbackType
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isObservingPlayback else { return }
                self.configure(env: env)
                self.observePlaybackType(env: env)   // re-arm for the next change
            }
        }
    }

    // MARK: - Per-present configuration

    /// Mutate the shared Now Playing template for the current item. Called just before the template
    /// is pushed. Safe to call repeatedly.
    func configure(env: AppEnvironment) {
        let template = CPNowPlayingTemplate.shared

        guard env.player.playbackType.isAudiobook else {
            // Not an audiobook (music/podcast/nothing) → strip audiobook-only chrome so speed/
            // chapters don't bleed onto other content. `updateNowPlayingButtons` is the ONLY way
            // to set buttons — the `nowPlayingButtons` array itself is readonly.
            template.updateNowPlayingButtons([])
            template.isUpNextButtonEnabled = false
            return
        }

        template.updateNowPlayingButtons([makeSpeedButton()])   // ≤ 5 buttons (framework hard cap)
        template.isUpNextButtonEnabled = true
        template.upNextTitle = "chapters"                        // relabels the built-in up-next slot
        if !isObserving {
            template.add(self)
            isObserving = true
        }
    }

    // MARK: - Speed button

    /// A `CPNowPlayingPlaybackRateButton` (iOS 14+) whose handler cycles the audiobook speed. The
    /// button renders the current rate itself from `MPNowPlayingInfoCenter`; the handler advances
    /// the player's real speed path and re-publishes the rate so the label re-renders. The handler
    /// is delivered on the main actor by the framework.
    private func makeSpeedButton() -> CPNowPlayingPlaybackRateButton {
        CPNowPlayingPlaybackRateButton { _ in
            CarPlayNowPlaying.shared.cycleSpeed()
        }
    }

    /// Advance to the next rate on the ladder, apply it live through the player's real speed path,
    /// and re-publish so the CarPlay/lock-screen rate label updates immediately.
    func cycleSpeed() {
        guard let env = CarPlayLink.shared.environment,
              env.player.playbackType.isAudiobook else { return }

        let current = env.player.audiobookSpeed
        let next = Self.nextRate(after: current)

        // THE live-speed call: applies engine.rate while playing AND re-pushes now-playing
        // internally (setLongFormSpeed → nowPlayingHook), so the CarPlay rate button / lock screen
        // refresh without a second hook call here (that would double-rebuild the info dict).
        env.player.setLongFormSpeed(next)
    }

    static func nextRate(after current: Float) -> Float {
        let idx = rates.firstIndex(where: { abs($0 - current) < 0.01 })
            ?? rates.firstIndex(of: 1.0)
            ?? 0
        return rates[(idx + 1) % rates.count]
    }

    // MARK: - Chapters (up-next observer)

    /// The built-in up-next button is observer-only (no handler block); it fires only when `isUpNextButtonEnabled` was set
    /// and this observer is registered, both done in `configure`.
    /// `nonisolated` because `CPNowPlayingTemplateObserver` is not UI-actor annotated in the SDK, so a `@MainActor`
    /// method can't satisfy it under Swift 6. It arrives on the main thread; we hop to the main actor immediately.
    nonisolated func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        Task { @MainActor in CarPlayNowPlaying.shared.presentChapters() }
    }

    private func presentChapters() {
        guard let interfaceController,
              let env = CarPlayLink.shared.environment,
              case .audiobook(let session) = env.player.playbackType else { return }
        let bookId = session.bookId

        // Don't stack chapter lists on repeated up-next taps — CarPlay caps the nav stack (~5) and
        // a second push would eventually fail. If Chapters is already on top, leave it be.
        if (interfaceController.topTemplate as? CPListTemplate)?.title == "chapters" { return }

        let template = CPListTemplate(title: "chapters", sections: [])
        setCarPlayListLoading(template)
        interfaceController.pushTemplate(template, animated: true) { _, _ in }

        Task { @MainActor in
            guard let sections = await self.sections(forBookId: bookId, env: env) else {
                setCarPlayListEmpty(
                    template, title: "couldn't load chapters",
                    subtitle: "check your connection and try again."
                )
                return
            }
            guard !sections.isEmpty else {
                setCarPlayListEmpty(
                    template, title: "no chapters",
                    subtitle: "this book has no chapter markers."
                )
                return
            }
            let capped = clampedForCarPlay(sections)
            var rows = capped.map { self.chapterRow(for: $0, env: env) }
            if capped.count < sections.count {
                rows.append(moreNoticeItem(remaining: sections.count - capped.count))
            }
            if #available(iOS 18.4, *) { template.showsSpinnerWhileEmpty = false }
            template.updateSections([CPListSection(items: rows)])
        }
    }

    /// One row per chapter. Tap SEEKS the already-playing book in place to the chapter's
    /// book-absolute start (`env.player.seek(to:)` — no re-fetch, no reload from 0). The completion
    /// block MUST be called or the row spins forever.
    private func chapterRow(for chapter: AudiobookSection, env: AppEnvironment) -> CPListItem {
        let item = CPListItem(text: chapter.title, detailText: carPlayTimeText(seconds: chapter.start))
        item.handler = { _, completion in
            Task { @MainActor in
                env.player.seek(to: chapter.start)
                completion()
            }
        }
        return item
    }

    /// Chapters live only on the fully-fetched `Audiobook`, not on the player's `BookSession`, so
    /// re-fetch by id on first use and cache. Returns cached sections on a book match; nil when the
    /// fetch failed (an empty list means the book has no chapters).
    private func sections(forBookId bookId: String, env: AppEnvironment) async -> [AudiobookSection]? {
        if cachedBookId == bookId, let cachedSections { return cachedSections }
        guard let book = try? await env.client.getAudiobook(id: bookId) else { return nil }
        cachedBookId = bookId
        cachedSections = book.sections ?? []
        return cachedSections
    }
}
