import XCTest
import MediaPlayer
@testable import Kima

/// The lock screen publishes what you hear (ticket 03, ADR 0001): the published playback state
/// derives from `transportDisplayState`, never a bare engine-identity read. One seam — drive the
/// engine truth on the controller, run the publish, read back the real system value. The build-20
/// bug's last surviving surface was here: during a fetch window the lock screen offered play
/// while a tap paused.
@MainActor
final class NowPlayingPublishTests: XCTestCase {

    private func controller() -> PlaybackController {
        PlaybackController(server: KimaServer(baseURL: URL(string: "http://test.local")!))
    }

    /// The music track every state test stages, so the publish path has a session to speak for.
    private func seededMusic() throws -> PlaybackController {
        let c = controller()
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        return c
    }

    /// The podcast session both long-form tests stage: one episode holding the session, with the
    /// lock-screen metadata a real load would set.
    private func seededPodcast() throws -> PlaybackController {
        let c = controller()
        let ep = try Episode.fixture("ep1")
        c.playbackType = .podcastEpisode(podcastId: "sh1", episode: ep, queue: [ep])
        c.longFormNowPlayingMeta = LongFormNowPlayingMeta(title: "seed one", artist: "seed station", coverURL: nil)
        return c
    }

    /// Published state is process-global; clear it so this class can't leak a session into others.
    override nonisolated func tearDown() {
        MainActor.assumeIsolated {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
        super.tearDown()
    }

    // MARK: - Fetch window (the bug)

    /// A session fetching its sound bytes publishes playing — the lock screen and Control Center
    /// show pause, matching the tap that will stop the fetch. The bare is-playing read published
    /// paused here: play offered while a tap paused.
    func testFetchWindowPublishesPlaying() throws {
        let c = try seededMusic()
        c.engine.wantsPlayback = true
        c.engine.status = .buffering
        c.nowPlayingHook?()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
    }

    /// The fetch window shows pause but does not run the clock: no sound is out yet, so the
    /// published rate stays zero — the scrubber holds its position instead of drifting and snapping.
    func testFetchWindowFreezesPositionWhileShowingPause() throws {
        let c = try seededMusic()
        c.engine.wantsPlayback = true
        c.engine.status = .loading
        c.nowPlayingHook?()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
        let rate = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double
        XCTAssertEqual(rate, 0.0)
    }

    // MARK: - The rest of the display states, published honestly

    /// Sound out: playing — the pause glyph a tap will honor.
    func testAudiblePublishesPlaying() throws {
        let c = try seededMusic()
        c.engine.isPlaying = true
        c.nowPlayingHook?()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
        let rate = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double
        XCTAssertEqual(rate, 1.0)   // the clock runs only when sound is
    }

    /// A paused session publishes paused: the lock screen offers play, and a tap resumes.
    func testPausedSessionPublishesPaused() throws {
        let c = try seededMusic()
        c.engine.status = .paused
        c.nowPlayingHook?()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
    }

    /// A resting session publishes stopped — the silent tail named by ticket 01's derivation reads
    /// as what it is, not as a paused transport. The old two-valued publish could not say this.
    func testStoppedSessionPublishesStopped() throws {
        let c = try seededMusic()
        c.engine.status = .idle   // staged, playback not wanted
        c.nowPlayingHook?()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .stopped)
    }

    /// A dead item publishes the play affordance: the system offers no retry glyph, and a tap on
    /// play retries through `togglePlayPause`'s precedence — honest without pretending otherwise.
    func testErroredItemPublishesPlayAffordance() throws {
        let c = try seededMusic()
        c.engine.status = .error
        c.engine.audioError = "stream died"
        c.nowPlayingHook?()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
    }

    /// An ended interruption publishes the play affordance: a tap starts sound, never auto-resumes —
    /// the same reading `EngineStatus.blocked` promises in-app.
    func testBlockedPublishesPlayAffordance() throws {
        let c = try seededMusic()
        c.engine.status = .blocked
        c.nowPlayingHook?()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
    }

    // MARK: - Long-form (podcast / audiobook path)

    /// The long-form branch publishes from the same derived value: a podcast episode fetching its
    /// sound shows pause on the lock screen too — the surface where build 20's mislabel lived.
    func testPodcastFetchWindowPublishesPlaying() throws {
        let c = try seededPodcast()
        c.engine.wantsPlayback = true
        c.engine.status = .buffering
        c.nowPlayingHook?()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
    }

    /// Long-form pause stays paused on the lock screen — the fetch fix must not read a resting
    /// podcast as playing.
    func testPodcastPausedPublishesPaused() throws {
        let c = try seededPodcast()
        c.engine.status = .paused
        c.nowPlayingHook?()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
    }
}
