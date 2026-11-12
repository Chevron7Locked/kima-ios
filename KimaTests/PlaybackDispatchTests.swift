import XCTest
@testable import Kima

/// The one tap-dispatch entry point (ticket 06): every content hero hands its membership rule
/// and the tap to the controller; resume-vs-pause-vs-start-over is decided there, never on the
/// page (ADR 0001 — identity dispatches, never appearance). One test per content kind × the
/// three decisions: paused-and-owned → resume, audible → pause, not-owned → start fresh.
@MainActor
final class PlaybackDispatchTests: XCTestCase {

    // MARK: - Track-set heroes (album, playlist, discover)

    /// The album/playlist/discover hero while their session sits paused: the tap resumes it in
    /// place — no queue replacement, no new play request (the re-spelled page branch's bug was
    /// falling into start-over here).
    func testTrackHeroTapResumesPausedOwnedSession() throws {
        let c = PlaybackController.stubbed()
        c.queue = [try Track.fixture("a"), try Track.fixture("b")]
        c.currentIndex = 0
        c.engine.status = .paused                      // the bug's exact state, literally

        c.handleHeroTap(trackIds: ["a", "z"], tracks: [try Track.fixture("z")])

        XCTAssertTrue(c.engine.wantsPlayback, "a paused owned session must resume")
        XCTAssertEqual(c.queue.map(\.id), ["a", "b"], "resuming must not replace the queue")
        XCTAssertEqual(c.playRequestCount, 0, "resuming is not a new play request")
    }

    /// The same hero while its sound plays: the opposite decision on the same ownership —
    /// pause what you hear, queue untouched.
    func testTrackHeroTapPausesWhileAudible() throws {
        let c = PlaybackController.stubbed()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        c.engine.wantsPlayback = true
        c.engine.applyTimeControlStatus(.playing)          // genuinely audible, mirrors and all

        c.handleHeroTap(trackIds: ["a"], tracks: [try Track.fixture("z")])

        XCTAssertFalse(c.engine.wantsPlayback, "an audible owned session must pause")
        XCTAssertEqual(c.queue.map(\.id), ["a"], "pausing must not replace the queue")
    }

    /// The fetch overlap: bytes on the way is audible (ADR 0001), so the hero shows pause
    /// through it and the tap must pause too — display and dispatch read the same precedence
    /// (CODING_STANDARDS §Precedence mirrors dispatch; this is the matrix's overlap state).
    func testTrackHeroTapPausesWhileFetching() throws {
        let c = PlaybackController.stubbed()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        c.engine.wantsPlayback = true
        c.engine.status = .loading               // fetching: isWaitingForAudio, not yet playing

        c.handleHeroTap(trackIds: ["a"], tracks: [try Track.fixture("z")])

        XCTAssertFalse(c.engine.wantsPlayback, "an owned session mid-fetch must pause the fetch")
        XCTAssertEqual(c.queue.map(\.id), ["a"], "pausing a fetch must not replace the queue")
    }

    /// Another page's session (or none): the same tap starts the given tracks fresh — the queue
    /// the page handed over, from its top, as one new play request.
    func testTrackHeroTapStartsFreshWhenNotOwned() throws {
        let c = PlaybackController.stubbed()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        c.engine.status = .paused

        c.handleHeroTap(trackIds: ["z"], tracks: [try Track.fixture("x"), try Track.fixture("y")])

        XCTAssertEqual(c.queue.map(\.id), ["x", "y"], "a not-owned tap must start the given tracks fresh")
        XCTAssertEqual(c.currentIndex, 0)
        XCTAssertEqual(c.playRequestCount, 1)
    }

    // MARK: - Predicate heroes (artist)

    /// The artist hero hands its own membership rule — the id-or-name fallback lives on the
    /// page — to the same dispatch: a paused session holding a track the page claims resumes
    /// in place, and the start action is never reached.
    func testPredicateHeroTapResumesPausedOwnedSession() throws {
        let c = PlaybackController.stubbed()
        c.queue = [Track.fixture("a", artist: .ref(id: nil, name: "Aurora"))]   // name-only: the fallback case
        c.currentIndex = 0
        c.engine.status = .paused

        var started = false
        c.handleHeroTap(owns: { $0.artist?.name == "Aurora" }, start: { started = true })

        XCTAssertTrue(c.engine.wantsPlayback, "a paused session holding the page's track must resume")
        XCTAssertFalse(started, "owning the session means never starting over")
    }

    /// The same hero over another artist's session: the tap runs the page's start action — the
    /// play-all fetch is the page's own — and dispatch itself touches nothing.
    func testPredicateHeroTapRunsStartActionWhenNotOwned() throws {
        let c = PlaybackController.stubbed()
        c.queue = [Track.fixture("a", artist: .ref(id: "other", name: "Other"))]
        c.currentIndex = 0
        c.engine.status = .paused

        var started = false
        c.handleHeroTap(owns: { $0.artist?.id == "aurora" }, start: { started = true })

        XCTAssertTrue(started, "a not-owned tap must run the page's start action")
        XCTAssertFalse(c.engine.wantsPlayback, "starting over is the page's job; dispatch must not also toggle")
    }

    /// The same hero while its sound plays — the opposite decision on the same predicate: pause
    /// what you hear, and never reach the start action.
    func testPredicateHeroTapPausesWhileAudible() throws {
        let c = PlaybackController.stubbed()
        c.queue = [Track.fixture("a", artist: .ref(id: "aurora", name: "Aurora"))]
        c.currentIndex = 0
        c.engine.wantsPlayback = true
        c.engine.applyTimeControlStatus(.playing)

        var started = false
        c.handleHeroTap(owns: { $0.artist?.id == "aurora" }, start: { started = true })

        XCTAssertFalse(c.engine.wantsPlayback, "an audible owned session must pause")
        XCTAssertFalse(started, "pausing is not starting over")
    }

    // MARK: - Podcast heroes (podcast detail)

    /// The podcast hero asks the show question — does main playback hold an episode of *this*
    /// show? Paused and owned: the tap resumes it; play-latest is never reached.
    func testPodcastHeroTapResumesPausedOwnedShow() throws {
        let c = PlaybackController.stubbed()
        let ep = try Episode.fixture("e1")
        c.playbackType = .podcastEpisode(podcastId: "sh1", episode: ep, queue: [ep])
        c.engine.status = .paused

        var started = false
        c.handleHeroTap(podcastId: "sh1", start: { started = true })

        XCTAssertTrue(c.engine.wantsPlayback, "a paused session of this show must resume")
        XCTAssertFalse(started, "owning the session means never playing latest")
    }

    /// The same hero while the episode plays: pause what you hear; play-latest untouched.
    func testPodcastHeroTapPausesWhileAudible() throws {
        let c = PlaybackController.stubbed()
        let ep = try Episode.fixture("e1")
        c.playbackType = .podcastEpisode(podcastId: "sh1", episode: ep, queue: [ep])
        c.engine.wantsPlayback = true
        c.engine.applyTimeControlStatus(.playing)

        var started = false
        c.handleHeroTap(podcastId: "sh1", start: { started = true })

        XCTAssertFalse(c.engine.wantsPlayback, "an audible owned show must pause")
        XCTAssertFalse(started, "pausing is not playing latest")
    }

    /// Another show holds the session: this hero's tap runs play-latest and dispatch touches
    /// nothing — a page never pauses another show's sound on its way to starting its own.
    func testPodcastHeroTapPlaysLatestWhenAnotherShowOwns() throws {
        let c = PlaybackController.stubbed()
        let ep = try Episode.fixture("e9")
        c.playbackType = .podcastEpisode(podcastId: "sh2", episode: ep, queue: [ep])
        c.engine.wantsPlayback = true
        c.engine.applyTimeControlStatus(.playing)

        var started = false
        c.handleHeroTap(podcastId: "sh1", start: { started = true })

        XCTAssertTrue(started, "a not-owned tap must run play-latest")
        XCTAssertTrue(c.engine.wantsPlayback, "dispatch must not pause another show's sound")
    }

    // MARK: - Audiobook heroes (detail, series)

    /// The book hero asks the book question — does main playback hold *this* book's session?
    /// Paused and owned: resume at position; the start action never runs.
    func testAudiobookHeroTapResumesPausedOwnedBook() throws {
        let c = PlaybackController.stubbed()
        c.playbackType = .audiobook(BookSession(bookId: "bk1", totalDuration: 100,
            files: [AudiobookTrack(index: 1, startOffset: 0, duration: 100)]))
        c.engine.status = .paused

        var started = false
        c.handleHeroTap(bookId: "bk1", start: { started = true })

        XCTAssertTrue(c.engine.wantsPlayback, "a paused session of this book must resume")
        XCTAssertFalse(started, "owning the session means never starting the book again")
    }

    /// The same hero while its sound plays: pause what you hear. The page's local
    /// `audible ? pause : resume` re-spelled exactly this decision from appearance alone.
    func testAudiobookHeroTapPausesWhileAudible() throws {
        let c = PlaybackController.stubbed()
        c.playbackType = .audiobook(BookSession(bookId: "bk1", totalDuration: 100,
            files: [AudiobookTrack(index: 1, startOffset: 0, duration: 100)]))
        c.engine.wantsPlayback = true
        c.engine.applyTimeControlStatus(.playing)

        var started = false
        c.handleHeroTap(bookId: "bk1", start: { started = true })

        XCTAssertFalse(c.engine.wantsPlayback, "an audible owned book must pause")
        XCTAssertFalse(started, "pausing is not starting the book again")
    }

    /// Another session (here a paused track queue) holds playback: the tap runs the page's
    /// play-book action; dispatch itself toggles nothing.
    func testAudiobookHeroTapStartsFreshWhenNotOwned() throws {
        let c = PlaybackController.stubbed()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        c.engine.status = .paused

        var started = false
        c.handleHeroTap(bookId: "bk1", start: { started = true })

        XCTAssertTrue(started, "a not-owned tap must run the page's play-book action")
        XCTAssertFalse(c.engine.wantsPlayback, "starting is the page's job; dispatch must not also toggle")
    }

    // MARK: - Awaited book hero (CarPlay rows fetch detail before they can start)

    /// The awaited form of the book question, for pages whose start action must fetch first.
    /// Paused and owned: the tap resumes in place and the awaited start — the re-fetch that
    /// could restart the book at 0 over the listener's real place — is never reached. That is
    /// CarPlay's double-tap guard (ticket 07) living in the dispatch, not on the surface.
    func testAwaitedBookHeroTapResumesPausedOwnedBook() async throws {
        let c = PlaybackController.stubbed()
        c.playbackType = .audiobook(BookSession(bookId: "bk1", totalDuration: 100,
            files: [AudiobookTrack(index: 1, startOffset: 0, duration: 100)]))
        c.engine.status = .paused

        var started = false
        let start: () async -> Void = { started = true }
        await c.handleHeroTap(bookId: "bk1", start: start)

        XCTAssertTrue(c.engine.wantsPlayback, "a paused session of this book must resume")
        XCTAssertFalse(started, "owning the session means never re-fetching the book")
    }

    /// The same awaited hero while its sound plays: the opposite decision on the same
    /// ownership — pause what you hear, and still no fetch. CarPlay's row kept asking this
    /// of raw engine state (`!isPlaying`) instead of asking the dispatch.
    func testAwaitedBookHeroTapPausesWhileAudible() async throws {
        let c = PlaybackController.stubbed()
        c.playbackType = .audiobook(BookSession(bookId: "bk1", totalDuration: 100,
            files: [AudiobookTrack(index: 1, startOffset: 0, duration: 100)]))
        c.engine.wantsPlayback = true
        c.engine.applyTimeControlStatus(.playing)

        var started = false
        let start: () async -> Void = { started = true }
        await c.handleHeroTap(bookId: "bk1", start: start)

        XCTAssertFalse(c.engine.wantsPlayback, "an audible owned book must pause")
        XCTAssertFalse(started, "pausing is not re-fetching the book")
    }

    /// Another session holds playback: the awaited start — fetch detail, then play — runs and
    /// has *finished* by the time dispatch returns (the caller's fetch-failure feedback waits
    /// on that), while dispatch itself toggles nothing.
    func testAwaitedBookHeroTapRunsAwaitedStartWhenNotOwned() async throws {
        let c = PlaybackController.stubbed()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        c.engine.status = .paused

        var started = false
        let start: () async -> Void = {
            try? await Task.sleep(nanoseconds: 10_000_000)   // a fetch-shaped pause
            started = true
        }
        await c.handleHeroTap(bookId: "bk1", start: start)

        XCTAssertTrue(started, "a not-owned tap must finish the page's fetch-and-play action")
        XCTAssertFalse(c.engine.wantsPlayback, "starting is the page's job; dispatch must not also toggle")
    }
}
