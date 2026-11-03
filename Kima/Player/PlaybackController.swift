import AVFoundation
import Foundation
import Observation

/// Business-logic layer above `PlaybackEngine`: queue state, shuffle/repeat, skip debounce, error policy. Views use
/// only this class. `@MainActor` throughout (AVFoundation state lives there). Stream URLs carry a short-lived ticket
/// (`resolveStreamToken`); only a ticketless server gets the login token. `NowPlayingController` is wired to
/// `nowPlayingHook`; remote commands route back here.
@MainActor
@Observable
final class PlaybackController {

    /// Bumped every time the user starts playback from the UI. The mini player watches this
    /// rather than the current track's id: tapping a mix that begins with the track already
    /// loaded changes no id, so an id diff leaves the bar minimized and the tap looks ignored.
    private(set) var playRequestCount = 0

    /// Record that the user asked to start playback. Extensions in other files cannot assign the
    /// counter directly (private setter), and that is the point: this is the one entry point.
    func notePlayRequest() { playRequestCount += 1 }

    // MARK: - Queue state
    // Internal (no `private(set)`) so PlaybackController+Queue.swift can mutate these.
    // Within the app module, views must not set these directly — use the public API.

    var queue: [Track] = []
    var currentIndex: Int = 0

    /// Permutation of queue indices for shuffle mode. `shuffleOrder[0]` is always the track
    /// that was playing when shuffle was toggled on (Fisher-Yates keep-current).
    var shuffleOrder: [Int] = []

    /// Current position within `shuffleOrder`; irrelevant when `isShuffle == false`.
    var shufflePosition: Int = 0

    var isShuffle: Bool = false
    var repeatMode: RepeatMode = .off

    // MARK: - Hooks

    /// Called after queue / track / play-state changes so the lock screen refreshes. Assigned in `init`.
    var nowPlayingHook: (() -> Void)?

    /// Called after queue / index / shuffle changes to schedule a debounced server save. Assigned by
    /// `AppEnvironment`. Not called from `hydrateFromServer` (server-applied state must not re-save).
    var syncHook: (() -> Void)?

    /// Owns the lock-screen / remote-command surface. Set in `init`; never nil afterwards.
    private var nowPlaying: NowPlayingController?

    // MARK: - Error tracking
    // Internal so PlaybackController+Queue.swift can read/write them.

    var consecutiveErrorCount: Int = 0

    /// Gates the first manual `next()` while `repeatMode == .one`: the first Next restarts the
    /// current track, only a second advances. Reset whenever a new track
    /// loads or the repeat mode changes.
    var repeatOneRestartConsumed = false

    // MARK: - Mid-stream recovery
    // Internal (no access modifier) so PlaybackController+Recovery.swift and
    // PlaybackController+Queue.swift can read/write them across the file boundary.

    /// Last-known MUSIC position (engine-relative seconds), refreshed every tick while playing
    /// and captured on pause. On a recoverable `.failed` (e.g. a paused + backgrounded stream
    /// whose connection dropped), the current item is rebuilt HERE, so resume()/togglePlayPause()
    /// and AirPod play never restart the track from 0. Long-form persists via `saveProgress`.
    var lastKnownMusicPosition: Double = 0

    /// Position of the current recovery cycle, in `recoveryPoint` units. A materially different
    /// position (> 1 s) starts a fresh cycle and resets `recoveryAttempts`; new content resets both.
    var recoveryPosition: Double = -1

    /// Bounded-retry counter for the current recovery cycle. Reset to 0 whenever an item reaches
    /// `.readyToPlay` (engine.onReady) — a recovery that re-buffered — or the position moves on.
    var recoveryAttempts: Int = 0

    /// Max in-place rebuilds for a single track/position before falling through to the existing
    /// full-stop / skip error policy, so a genuinely-unplayable track still eventually stops.
    let maxRecoveryAttempts = 3

    /// Track id whose "is it gone?" server check already ran for the current load
    /// (`checkGoneThenRecover`). Reset per track in `loadCurrentTrack`, so a rebuild that fails
    /// again goes straight to the rebuild ladder instead of asking again.
    var goneCheckedTrackId: String?

    /// Stall rebuilds of one item with under a minute of progress between them (`handleStalled`),
    /// and the item and position of the last one.
    @ObservationIgnored var stallCount = 0
    @ObservationIgnored var stallAnchor: (item: String?, position: Double)?

    // MARK: - Long-form state
    // Internal so PlaybackController+LongForm.swift can mutate these.

    /// What content type is currently playing. Views observe this to adapt controls.
    var playbackType: LongFormPlaybackType = .track

    /// 1-based `AudiobookTrack.index` of the file currently loaded in AVPlayer.
    /// Used for book-absolute time conversion and file-advance logic.
    var currentLongFormFileIndex: Int = 0

    /// Minimal metadata for the lock screen when `currentTrack == nil` (long-form).
    var longFormNowPlayingMeta: LongFormNowPlayingMeta?

    /// Audiobook playback speed (0.75–2.0). Loaded from UserDefaults in init.
    /// Internal (set from PlaybackController+LongForm.swift) — views read it for the speed picker.
    var audiobookSpeed: Float = 1.0

    /// Podcast playback speed (0.75–2.0). Loaded from UserDefaults in init.
    var podcastSpeed: Float = 1.0

    /// Book-absolute (or episode-absolute) seconds of the last successful progress save.
    /// Initialized to -1 so the very first save always fires (dedup threshold: 0.5 s).
    var lastSavedProgressTime: Double = -1

    /// The audiobook or episode that just finished: its progress saves stop, so the pause at the end
    /// can't save it as unfinished. Cleared by a seek and by a new session.
    @ObservationIgnored var finishedLongFormId: String?

    /// Apple id of a not-followed show whose first episode is playing as a sample: nothing is saved, nothing is
    /// marked finished, and nothing plays after it. Cleared by a new session.
    var podcastSampleItunesId: String?

    /// The station playing (library or artist radio), which refills the queue as it nears its end; nil otherwise.
    /// Observed, so the shuffle button can show that an in-order station has it off. Ended with `endStation()`.
    var stationSession: StationSession?

    /// True while the queue plays in order (a vibe queue, an in-order station): shuffle is off and unavailable.
    var queuePlaysInOrder: Bool { isVibeQueue || stationSession?.inOrder == true }

    /// The server's answer for what plays after the podcast episode playing, asked when it becomes ready.
    @ObservationIgnored var podcastNextLookup: PodcastNextLookup?
    /// How long an episode's end waits for that answer before playing the list's next row.
    @ObservationIgnored var podcastNextDeadline: Duration = .seconds(3)

    /// The latest progress save. Each save waits for the one before, so they reach the server in order.
    @ObservationIgnored var progressSaveChain: Task<Void, Never>?

    /// Reference to the API client for in-flight progress saves. Set at session start;
    /// cleared in `stopLongForm()` to prevent phantom saves after teardown.
    var longFormAPIClient: KimaAPIClient?

    /// Reference to the API client for stream-ticket fetching. Set by AppEnvironment
    /// after init; kept non-nil for the duration of the authenticated session.
    /// Used by music-track loaders; long-form loaders use `longFormAPIClient` instead.
    var apiClient: KimaAPIClient?

    /// Keeps a stream ticket minted ahead of any tap. Started once by `AppEnvironment`.
    /// Internal, not private: the keeper loop lives in `PlaybackController+Streaming.swift`,
    /// and Swift denies extensions in other files access to private members.
    var ticketWarmTask: Task<Void, Never>?

    /// Cancellable 15-second progress-save timer task. Internal — managed by the long-form extensions.
    var progressTimerTask: Task<Void, Never>?

    /// NotificationCenter token for `UIApplication.willResignActiveNotification`.
    var progressResignToken: NSObjectProtocol?

    // MARK: - Vibe state
    // Internal (no access modifier) so PlaybackController+Vibe.swift can mutate these —
    // same pattern as consecutiveErrorCount / repeatOneRestartConsumed above.
    // Views must not set these directly; use toggleVibeMode(client:), playVibeQueue and checkVibeAvailability(client:).

    /// What built the current queue (song path, play similar, blend); nil for an ordinary queue. The one
    /// record of a vibe queue: the vibe buttons read it, and `play(tracks:)` clears it.
    /// Start a vibe queue with `playVibeQueue`.
    var queueOrigin: QueueOrigin? = nil

    /// True during any vibe queue (play similar, song path or blend). Vibe queues play in order.
    var isVibeQueue: Bool { queueOrigin != nil }

    /// Set while a new vibe queue waits on "replace the current queue?"; see `confirmVibeReplace`.
    var vibeReplacePrompt: VibeReplacePrompt? = nil
    var vibeReplaceContinuation: CheckedContinuation<Bool, Never>? = nil

    /// Screens that can show the replace question, oldest first; only the last one presents it.
    var vibeReplaceHosts: [UUID] = []

    /// True while the GET /api/vibe/similar fetch is in flight (drives the spinner).
    var isVibeLoading = false

    /// Non-nil when the last toggle failed — read by the view for an error toast.
    /// Cleared on the next successful toggle or stop.
    var vibeError: String? = nil

    /// Non-nil after a successful toggle (start = "Vibe mode on — N similar tracks queued";
    /// stop = "Vibe mode off"). FullPlayerView observes this, forwards to ToastCenter, then
    /// clears it — keeps PlaybackController (Core) decoupled from DesignSystem.
    var vibeNotice: String? = nil

    /// One-shot notice from the player itself (e.g. a gone track was skipped). AppShellView
    /// forwards it to ToastCenter and clears it — same Core→DesignSystem bridge as `vibeNotice`.
    var playerNotice: String? = nil

    /// Track id → fused cosine similarity (0–1) for a play similar queue, from `/vibe/similar`; the
    /// source track maps to `1.0`. Read by `vibeMatchScore` for the current track's badge.
    var vibeSimilarities: [String: Double] = [:]

    /// Availability of CLAP embeddings in the library: nil = not yet fetched, false = unavailable (button hidden),
    /// true = available. Re-checked by `checkVibeAvailability(client:)`; a failed fetch leaves it as it was.
    var vibeEmbeddingsAvailable: Bool? = nil
    var vibeFeaturesCheckedAt: Date? = nil

    // MARK: - Sleep timer

    /// Session-scoped sleep timer. Owned here so the countdown Task survives
    /// FullPlayerView dismiss/reopen. Views access it via `player.sleepTimer`.
    /// `onExpiry` is wired in `init` to call `pause()` directly.
    let sleepTimer = SleepTimerModel()

    // MARK: - Session caches (survive FullPlayerView dismiss/reopen)

    /// Waveform peak arrays keyed by track ID. Populated on first fetch; checked before
    /// any network call so FullPlayerView reopens show the waveform immediately.
    /// FIFO-capped (100 tracks) so a large library cannot grow it without bound.
    @ObservationIgnored var waveformCache = KeyedFIFOCache<[Double]>(limit: 100)

    /// Lyrics responses keyed by track ID. Checked before network call so LyricsPanel
    /// reopens skip the loading flash. FIFO-capped (100) for the same reason.
    @ObservationIgnored var lyricsCache = KeyedFIFOCache<LyricsResponse>(limit: 100)

    /// Detail-filled tracks keyed by id (see `hydrateCurrentTrackCoverIfNeeded`): a fresh bare
    /// copy of an already-filled track is re-filled from here with no refetch.
    /// FIFO-capped (500 — a full Track is small; the cap bounds a long session).
    @ObservationIgnored var hydratedTracks = KeyedFIFOCache<Track>(limit: 500)

    /// Track ids with a detail fetch in flight — dedupes concurrent loads of one id. Cleared
    /// when the fetch ends, success or not, so a failed fill retries on the next load.
    @ObservationIgnored var hydrationInFlight: Set<String> = []

    // MARK: - Skip debounce
    // `skipTask`, `skipBase`, `skipAccumulator` are internal (no `private`) so
    // PlaybackController+Skip.swift can implement the debounce methods across the file boundary.

    /// Instant UI time shown during a 200ms skip debounce. Normally mirrors
    /// `engine.currentTime`; overridden while a skip is accumulating. The full player
    /// uses this for the seek slider so the handle moves immediately on each tap.
    var displayTime: Double = 0

    var skipTask: Task<Void, Never>?
    var skipBase: Double = 0
    var skipAccumulator: Double = 0

    // MARK: - Play reporting
    // Wired in PlaybackController+PlayReporting.swift; state lives here so the
    // main file's tick/seek hooks can reach it (same pattern as skip debounce).

    /// Listening measurement for the current music track. Reset on track change
    /// via the meter's own trackId guard — a late duration keeps the reported flag.
    var playMeter = ListenMeter(durationSeconds: nil)

    /// Track id the meter is currently measuring; nil = idle (long-form / empty).
    var meterTrackId: String?

    /// Client for fire-and-forget POST /plays. Assigned by `attachPlayReporting`.
    var playReportClient: KimaAPIClient?

    /// Wait before the one retry of a play report that didn't get through.
    @ObservationIgnored var playReportRetryDelay: Duration = .seconds(30)

    /// 60s heartbeat while background-playing (iOS delta vs web; +60s only —
    /// a suspend gap is not credited; server dedup = track length).
    @ObservationIgnored var playHeartbeatTask: Task<Void, Never>?

    /// UIApplication background/foreground/terminate observer tokens.
    @ObservationIgnored var playReportTokens: [NSObjectProtocol]?

    deinit {
        // NotificationCenter retains app-level observer blocks forever, and AppEnvironment is rebuilt on every
        // sign-in, so without removal here each session leaks 4 observers. The heartbeat task captures self
        // weakly and exits at its next wake-up, so it needs no cancel.
        if let tokens = playReportTokens {
            NotificationCenter.default.removeObserver(tokens)
        }
    }

    // MARK: - Private internals

    let engine: PlaybackEngine
    let server: KimaServer

    // MARK: - Init

    init(server: KimaServer) {
        self.server = server
        self.engine = PlaybackEngine()
        // `nowPlaying` must exist before the engine callbacks are wired (the tick reads it).
        self.nowPlaying = NowPlayingController(controller: self, server: server)
        wireEngineCallbacks()
        nowPlayingHook = { [weak self] in self?.nowPlaying?.refresh(isUserAction: true) }
        // Load persisted long-form speeds (default 1.0 when not yet stored).
        let abSpeed = UserDefaults.standard.float(forKey: "kima.speed.audiobook")
        audiobookSpeed = abSpeed > 0 ? abSpeed : 1.0
        let podSpeed = UserDefaults.standard.float(forKey: "kima.speed.podcast")
        podcastSpeed = podSpeed > 0 ? podSpeed : 1.0
        // Sleep timer: wire expiry to pause here so the action fires regardless of whether
        // FullPlayerView is currently presented. The weak capture avoids a retain cycle
        // (sleepTimer is owned by self; onExpiry would form a strong reference back).
        sleepTimer.onExpiry = { [weak self] in self?.pause() }
        sleepTimer.currentPlayback = { [weak self] in self?.playbackType ?? .track }
    }

    // MARK: - Engine callback wiring

    private func wireEngineCallbacks() {
        engine.onEnded   = { [weak self] in    self?.handleEnded() }
        engine.onFailed  = { [weak self] _ in self?.handleFailed() }
        engine.onStalled = { [weak self] in self?.handleStalled() }
        engine.onPlaying = { [weak self] in
            guard let self else { return }
            self.consecutiveErrorCount = 0
            // Re-assert the playback speed on every resume: `player.play()` resets `AVPlayer.rate`
            // to 1.0, so a long-form item would drop to 1.0x after any pause or interruption.
            // Music has no custom rate.
            switch self.playbackType {
            case .audiobook:      self.engine.player.rate = self.audiobookSpeed
            case .podcastEpisode: self.engine.player.rate = self.podcastSpeed
            case .track:          break
            }
            self.nowPlayingHook?()
        }
        // A successful (re)load — clear the recovery budget so a later idle-drop can
        // recover afresh. A genuinely-unplayable track never reaches readyToPlay, so its budget
        // is never reset and the bounded retries still exhaust into the full-stop policy.
        engine.onReady = { [weak self] in
            guard let self else { return }
            self.recoveryAttempts = 0
            self.recoveryPosition = -1
            // While this stream plays, mint + warm the NEXT stream URL off the critical
            // path, so an advance hits a warmed asset instead of a cold ticket-mint + TTFB.
            self.prefetchNextStream()
        }
        // Fires whenever isPlaying toggles (interruptions, route changes, user pauses); a pause also
        // saves long-form progress so the position is persisted immediately.
        engine.onPlaybackStateChanged = { [weak self] in
            guard let self else { return }
            self.nowPlayingHook?()
            if !self.engine.isPlaying {
                self.saveProgress()
            }
        }
        // 1 Hz tick — sync displayTime (book-absolute for long-form) + push lock-screen position.
        engine.onTick = { [weak self] in
            guard let self else { return }
            // Keep displayTime synced to current position when not in a skip debounce.
            if self.skipTask == nil {
                self.displayTime = self.currentTime  // long-form aware
            }
            // Keep a running snapshot of the music position so a recoverable failure can
            // rebuild the item exactly where it dropped (never restart from 0).
            if !self.playbackType.isLongForm {
                self.lastKnownMusicPosition = self.engine.currentTime
            }
            // Play reporting: feed the 1 Hz position to the listen meter (music only;
            // the meter ignores long-form / empty queue).
            self.observePlayPosition(trackId: self.currentTrack?.id)
            self.nowPlaying?.refresh(isUserAction: false)
        }
    }
}
