import XCTest
@testable import Kima

/// The shared audible derivation (ADR 0001): display reads key on engine truth, identity only
/// scopes which item. One seam — the controller every page asks — matrix: each query ×
/// {audible, paused-but-current, other item} × waiting-for-audio.
@MainActor
final class PlaybackAudibleTests: XCTestCase {

    private func controller() -> PlaybackController {
        PlaybackController(server: KimaServer(baseURL: URL(string: "http://test.local")!))
    }

    // MARK: - displayState(of:): the row-glyph triad

    /// Nothing audible, "a" holds the session: it reads .current (findable, resumable), never .playing.
    func testCurrentTrackReadsCurrentWhenSilent() throws {
        let c = controller()
        c.queue = [try Track.fixture("a"), try Track.fixture("b")]
        c.currentIndex = 0
        XCTAssertEqual(c.displayState(of: "a"), .current)
        XCTAssertEqual(c.displayState(of: "b"), .none)
    }

    /// The engine is putting out sound and "a" holds the session: it reads .playing, its neighbour stays .none.
    func testCurrentTrackReadsPlayingWhileAudible() throws {
        let c = controller()
        c.queue = [try Track.fixture("a"), try Track.fixture("b")]
        c.currentIndex = 0
        c.engine.isPlaying = true
        XCTAssertEqual(c.displayState(of: "a"), .playing)
        XCTAssertEqual(c.displayState(of: "b"), .none)
    }

    /// "a" is fetching sound bytes (no audio yet): the control holds .playing — a stall must not blink it to play.
    func testCurrentTrackHoldsPlayingWhileWaitingForAudio() throws {
        let c = controller()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        c.engine.wantsPlayback = true
        c.engine.status = .buffering
        XCTAssertEqual(c.displayState(of: "a"), .playing)
    }

    // MARK: - isAudible(where:): the membership of heroes and grid cards

    /// The album-hero question while its track is audible: yes for its own album, no for the other.
    func testMembershipMatchesCurrentItemWhenAudible() throws {
        let c = controller()
        c.queue = [try Track.fixture("a", albumId: "al1"), try Track.fixture("b", albumId: "al2")]
        c.currentIndex = 0
        c.engine.isPlaying = true
        XCTAssertTrue(c.isAudible { $0.album?.id == "al1" })
        XCTAssertFalse(c.isAudible { $0.album?.id == "al2" })
    }

    /// Same album holding the session, engine silent: nothing is audible anywhere.
    func testMembershipFalseWhenPaused() throws {
        let c = controller()
        c.queue = [try Track.fixture("a", albumId: "al1")]
        c.currentIndex = 0
        XCTAssertFalse(c.isAudible { $0.album?.id == "al1" })
    }

    /// The same album fetching its sound: audible again — the cell that keeps a hero from
    /// flickering to play during buffering.
    func testMembershipTrueWhileWaitingForAudio() throws {
        let c = controller()
        c.queue = [try Track.fixture("a", albumId: "al1"), try Track.fixture("b", albumId: "al2")]
        c.currentIndex = 0
        c.engine.wantsPlayback = true
        c.engine.status = .buffering
        XCTAssertTrue(c.isAudible { $0.album?.id == "al1" })
        XCTAssertFalse(c.isAudible { $0.album?.id == "al2" })
    }

    // MARK: - isAudible(trackIds:) / ownsSession(forTrackIds:): the hero action bars

    /// The playlist/album-hero pair, one seam apart: display lights on audible membership,
    /// dispatch reads session ownership — independent through pause and buffering.
    func testTrackIdSetAudibilityAndSessionOwnership() throws {
        let c = controller()
        c.queue = [try Track.fixture("a"), try Track.fixture("b")]
        c.currentIndex = 0
        let mine: Set<String> = ["a", "z"]
        let theirs: Set<String> = ["b"]
        XCTAssertFalse(c.isAudible(trackIds: mine))        // holds the session, silent
        XCTAssertTrue(c.ownsSession(forTrackIds: mine))    // dispatch: resume, not start over
        XCTAssertFalse(c.ownsSession(forTrackIds: theirs)) // another page's set never owns
        c.engine.isPlaying = true
        XCTAssertTrue(c.isAudible(trackIds: mine))         // its sound plays
        XCTAssertFalse(c.isAudible(trackIds: theirs))      // and never for the other set
        c.engine.isPlaying = false
        c.engine.wantsPlayback = true
        c.engine.status = .buffering
        XCTAssertTrue(c.isAudible(trackIds: mine))         // steady through buffering
    }

    // MARK: - isAudible(bookId:)

    /// The audiobook-card question: lit only while that book's sound plays — not for holding the
    /// session paused, not for a sibling card, and steady through buffering.
    func testAudiobookAudibility() throws {
        let c = controller()
        c.playbackType = .audiobook(BookSession(bookId: "bk1", totalDuration: 100,
            files: [AudiobookTrack(index: 1, startOffset: 0, duration: 100)]))
        XCTAssertFalse(c.isAudible(bookId: "bk1"))   // holds the session, silent
        c.engine.isPlaying = true
        XCTAssertTrue(c.isAudible(bookId: "bk1"))    // its sound plays
        XCTAssertFalse(c.isAudible(bookId: "bk2"))   // a sibling card never lights
        c.engine.isPlaying = false
        c.engine.wantsPlayback = true
        c.engine.status = .loading
        XCTAssertTrue(c.isAudible(bookId: "bk1"))    // fetching its sound still counts
    }

    // MARK: - transportDisplayState: the one value both transport controls render

    /// The engine is putting out sound: the transport reads .playing — pause glyph, a tap stops what you hear.
    func testTransportReadsPlayingWhileAudible() throws {
        let c = controller()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        c.engine.isPlaying = true
        XCTAssertEqual(c.transportDisplayState, .playing)
    }

    /// A session fetching its sound bytes reads .waiting — the pause-consistent hold (a tap now
    /// stops the fetch), in both the loading and the buffering half of the window.
    func testTransportHoldsWaitingWhileFetchingSound() throws {
        let c = controller()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        c.engine.wantsPlayback = true
        c.engine.status = .loading
        XCTAssertEqual(c.transportDisplayState, .waiting)
        c.engine.status = .buffering
        XCTAssertEqual(c.transportDisplayState, .waiting)
    }

    /// An errored item reads .retry — the arrow a tap acts on — even mid-fetch-want, never a mask.
    func testTransportReadsRetryOnError() throws {
        let c = controller()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        c.engine.wantsPlayback = true
        c.engine.status = .error
        c.engine.audioError = "stream died"
        XCTAssertEqual(c.transportDisplayState, .retry)
    }

    /// The overlap state pins display to dispatch's precedence (ADR 0001): with sound already out
    /// and the status errored, this reads .playing — a tap pauses what you hear, never retries.
    func testTransportPlayingOutranksError() throws {
        let c = controller()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        c.engine.isPlaying = true
        c.engine.status = .error
        XCTAssertEqual(c.transportDisplayState, .playing)
        XCTAssertEqual(c.transportDisplayState.accessibilityLabel, "pause")
    }

    /// An interruption that ended without resume intent reads .blocked — a play glyph whose tap starts sound.
    func testTransportReadsBlockedAfterEndedInterruption() throws {
        let c = controller()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        c.engine.status = .blocked
        XCTAssertEqual(c.transportDisplayState, .blocked)
    }

    /// The silent tail maps honestly for downstream (ticket 03): a held session reads .paused,
    /// nothing loaded — or staged but not started — reads .stopped. Both show play; a tap starts sound.
    func testTransportSilentTailMapsEngineRestingStates() throws {
        let c = controller()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        c.engine.status = .paused
        XCTAssertEqual(c.transportDisplayState, .paused)
        c.engine.status = .loading   // staged, playback not wanted: still resting, not waiting
        XCTAssertEqual(c.transportDisplayState, .stopped)
        c.engine.status = .idle
        XCTAssertEqual(c.transportDisplayState, .stopped)
    }

    /// The display value carries its own glyph and label — both controls render one answer.
    /// Glyphs and labels are today's transport renderings; a label says what a tap honors (ADR 0001).
    func testTransportDisplayCarriesGlyphAndLabel() throws {
        let c = controller()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0

        c.engine.isPlaying = true
        XCTAssertEqual(c.transportDisplayState.systemImage, "pause.fill")
        XCTAssertEqual(c.transportDisplayState.accessibilityLabel, "pause")

        c.engine.isPlaying = false
        c.engine.wantsPlayback = true
        c.engine.status = .buffering
        XCTAssertNil(c.transportDisplayState.systemImage)              // spinner instead of a glyph
        XCTAssertEqual(c.transportDisplayState.accessibilityLabel, "pause")  // a tap stops the fetch
        XCTAssertEqual(c.transportDisplayState.accessibilityValue, "loading")

        c.engine.wantsPlayback = false
        c.engine.status = .error
        XCTAssertEqual(c.transportDisplayState.systemImage, "arrow.clockwise")
        XCTAssertEqual(c.transportDisplayState.accessibilityLabel, "retry playback")

        for status in [EngineStatus.blocked, .paused, .idle] {         // the play-glyph family
            c.engine.status = status
            XCTAssertEqual(c.transportDisplayState.systemImage, "play.fill")
            XCTAssertEqual(c.transportDisplayState.accessibilityLabel, "play")
            XCTAssertEqual(c.transportDisplayState.accessibilityValue, "")
        }
    }

    // MARK: - Podcast: audible episode + session ownership (build-20's shape)

    /// The detail page's two reads: rows light the audibly playing episode only, and the hero
    /// dispatches on owns-session — display and dispatch never trade truths.
    func testPodcastAudibleEpisodeAndSessionOwnership() throws {
        let c = controller()
        let ep = try Episode.fixture("ep1")
        c.playbackType = .podcastEpisode(podcastId: "sh1", episode: ep, queue: [ep])
        XCTAssertNil(c.audiblePodcastEpisodeId)             // silent holder: nothing lit
        XCTAssertTrue(c.ownsPodcastSession("sh1"))          // dispatch: resume, not start over
        XCTAssertFalse(c.ownsPodcastSession("sh2"))         // another show: starts fresh
        c.engine.isPlaying = true
        XCTAssertEqual(c.audiblePodcastEpisodeId, "ep1")    // audible: that episode lights
        c.engine.isPlaying = false
        c.engine.wantsPlayback = true
        c.engine.status = .buffering
        XCTAssertEqual(c.audiblePodcastEpisodeId, "ep1")    // steady through buffering
    }
}
