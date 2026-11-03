import AVFoundation
import Foundation
import Observation
import OSLog

/// Low-level wrapper over exactly one `AVPlayer` (not `AVQueuePlayer`); `PlaybackController` owns shuffle /
/// repeat / up-next by loading the next item on `onEnded`. `@MainActor` throughout: AVPlayer and AVAudioSession
/// are main-thread-affine, and KVO blocks are non-isolated so they hop back via `Task { @MainActor }`.
/// `generation` drops stale observer callbacks; `loadEpoch` orders play intents.
@MainActor
@Observable
final class PlaybackEngine {

    // MARK: - Published state

    var status: EngineStatus = .idle
    var isPlaying: Bool = false

    /// Updated at 1 Hz by the periodic time observer while `status ∈ {playing, buffering}`.
    /// Suppressed during the pending-seek transition to avoid a 0-position flash.
    var currentTime: Double = 0

    /// Set when AVPlayerItem duration resolves; 0 while unknown.
    var duration: Double = 0

    var isBuffering: Bool = false

    /// Non-nil when `status == .error`. Surfaced as user-facing copy by the UI.
    var audioError: String?

    // MARK: - Seams for PlaybackController

    /// Set by `PlaybackController` to receive `AVPlayerItemDidPlayToEndTime`. The controller
    /// implements the TRACK queue-advance logic.
    var onEnded: (() -> Void)?

    /// Set by `PlaybackController` to handle terminal item failures.
    var onFailed: ((Error?) -> Void)?

    /// Set by `PlaybackController`: the stall watchdog gave up on the current item (see +Stall).
    var onStalled: (() -> Void)?

    /// Set by `PlaybackController` to reset `consecutiveErrorCount` on a successful
    /// transition into `.playing`.
    var onPlaying: (() -> Void)?

    /// Set by `PlaybackController` to reset the mid-stream recovery budget whenever an item
    /// successfully reaches `.readyToPlay` — a recovery that re-buffered counts as success even
    /// when it lands paused. Fires on every successful (re)load, so a genuinely-unplayable track
    /// (which never reaches `.readyToPlay`) still exhausts its bounded retries and stops.
    var onReady: (() -> Void)?

    /// Set by `PlaybackController` to receive notifications whenever `isPlaying`
    /// toggles — including interruption-driven pauses and route-change pauses. Used to
    /// push an immediate lock-screen update on any play/pause state change.
    var onPlaybackStateChanged: (() -> Void)?

    /// Set by `PlaybackController` to receive the 1 Hz periodic-time tick. Used to
    /// push throttled lock-screen position updates (≤ once per 5 s) during normal playback.
    var onTick: (() -> Void)?

    // MARK: - Stored properties (internal so +Session / +Observers extensions can access them)

    /// `let` so it is accessible from `deinit` without actor-isolation.
    let player: AVPlayer

    /// Monotonic load counter; used to reject stale KVO/notification completions.
    var generation: Int = 0

    /// Play-intent claim counter. `generation` cannot order load intents (in-flight loads share one value), so this
    /// bumps on every event that takes ownership of the player: a mint (`claimLoad`), a landing `load()`, and a
    /// teardown (`clear` / `signalExternalError`). Monotonic, never zeroed. A claim survives while
    /// `loadEpoch == claim`; bumps are main-actor-serial, so the newest claim wins.
    var loadEpoch: Int = 0

    /// `loadEpoch` as of the last landing or teardown; differs from it while a claim is outstanding.
    var landedEpoch: Int = 0

    /// Claim a fresh play-intent; call BEFORE the async hop (ticket fetch) of any load.
    /// The outgoing item's late callbacks (its end, a failure, a seek completion) belong to the old
    /// intent and are dropped, or an end during the ticket fetch would advance the queue twice.
    func claimLoad() -> Int {
        loadEpoch += 1
        generation += 1
        cancelStallWatchdog()
        return loadEpoch
    }

    /// True when `claim` is still the active play-intent (no newer claim and no
    /// teardown since it was minted). Checked after the async hop; the check→load
    /// stretch is sync on the MainActor, so nothing can interleave a claim there.
    func isCurrentLoad(_ claim: Int) -> Bool { loadEpoch == claim }

    /// A load was claimed and hasn't landed: the player still holds the previous item.
    var isLoadPending: Bool { loadEpoch != landedEpoch }

    /// Seek position applied at `.readyToPlay` before `play()`; cleared once that seek lands.
    var pendingSeek: Double?
    /// Last audio-session mode claimed; reused by load() and interruption-end so a spoken-audio
    /// session isn't reset to .default.
    var sessionMode: AVAudioSession.Mode = .default

    // Not observable state: `@ObservationIgnored` keeps `@Observable` from rewriting them into
    // computed properties, which is the only way `nonisolated(unsafe)` takes effect. It lets
    // `deinit` (not actor-isolated) invalidate the observations and remove the observer tokens.
    @ObservationIgnored nonisolated(unsafe) var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored nonisolated(unsafe) var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored nonisolated(unsafe) var durationObservation: NSKeyValueObservation?
    @ObservationIgnored nonisolated(unsafe) var endedToken: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) var periodicTimeToken: Any?

    /// AVAudioSession interruption / route-change observer tokens.
    @ObservationIgnored nonisolated(unsafe) var interruptionToken: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) var routeChangeToken: NSObjectProtocol?

    /// Whether the user wants sound: set by `play()` / `pause()` and a load's `autoplay`, never by
    /// KVO, so an interruption or a failure can't race it. Read when an item becomes ready, when an
    /// interruption ends, and by the stall watchdog.
    var wantsPlayback = false

    /// `wantsPlayback` when the item failed or stalled, so the controller's recovery restores it
    /// (playing → resume; paused → stay paused) after rebuilding the item at the saved position.
    var wasPlayingBeforeFailure = false

    /// How long the engine may wait for audio the user asked for before giving up on the item.
    var stallLimit: Duration = .seconds(15)
    @ObservationIgnored var stallTask: Task<Void, Never>?

    #if DEBUG
    /// DEBUG: the ⚡︎ menu's "simulate stall" holds the engine in buffering (see +Stall).
    var debugStalled = false
    #endif

    /// Applies the playback category and activates the session. A seam so tests can make iOS refuse it.
    @ObservationIgnored var activateSession: @MainActor (AVAudioSession.Mode) throws -> Void = { mode in
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: mode)
        try session.setActive(true)
    }

    // MARK: - Logger (shared with the extensions)

    let logger = Logger(subsystem: "com.chevron7locked.kima", category: "engine")

    /// `true` when the current item's load used a prefetched stream URL.
    /// Read by the `.readyToPlay` probe to label measured gaps warm/cold. Cleared per load.
    var loadUsedPrefetchedURL = false

    /// Last status reported by `handleItemStatus` for the current load generation.
    /// Consecutive duplicate deliveries are dropped: the warmed-handoff sync path and a
    /// background KVO hop can both report the same transition, and recovery-attempt
    /// counting must not double-charge one real failure.
    var lastDeliveredStatus: AVPlayerItem.Status?

    /// True once the current load generation reached `.readyToPlay`. A failure on a load that
    /// never got there is the controller's cue to ask the server whether the track still exists
    /// (`PlaybackController.checkGoneThenRecover`). Reset per `load(url:)`.
    var currentLoadReachedReady = false

    /// Wall-clock instant of the current `load(url:)` — the `.readyToPlay` probe measures the
    /// full build→ready window (the audible "stops between songs" gap) from this stamp.
    var loadStartedAt = Date.distantPast

    /// Warmed `AVURLAsset` from `prepareStream(url:)` (advance prefetch). `load(url:)`
    /// consumes it when the URL matches (creates the item from the SAME asset, reusing its
    /// byte-range reads) and discards it otherwise. Retained here so AVFoundation keeps its
    /// in-flight resource loading alive across the track-advance gap.
    var prefetchedAsset: AVURLAsset?

    // MARK: - Init

    init() {
        player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = true
        setupPeriodicTimeObserver()
        setupTimeControlObservation()
        registerSessionObservers()
    }

    // MARK: - Load

    /// Replace the current item and stage or begin playback. `url` is the authenticated stream URL. `autoplay`
    /// calls `play()` after any pending seek lands. `seekTo` (seconds, ignored when <= 0) is applied at
    /// `.readyToPlay` before play to prevent a flash of position 0.
    func load(url: URL, autoplay: Bool, seekTo: Double? = nil) {
        let myGen = nextGeneration()
        loadEpoch += 1  // a landed load retires every in-flight play-intent claim
        landedEpoch = loadEpoch
        teardownItemObservers()
        cancelStallWatchdog()
        #if DEBUG
        debugStalled = false
        #endif

        // Measurement probe: stamp the gap start; the .readyToPlay handler logs the
        // full build→ready window (retrieve via `log show --predicate 'subsystem ==
        // "com.chevron7locked.kima"'`) — the audible stops-between-songs window.
        loadStartedAt = Date.now
        lastDeliveredStatus = nil   // dedupe tracker is per-load-generation
        currentLoadReachedReady = false
        #if DEBUG
        logger.info("KIMA_AUDIO load-start gen=\(myGen, privacy: .public) autoplay=\(autoplay, privacy: .public)")
        #endif

        // Stop the outgoing item before the swap. `AVPlayer.rate` persists across `replaceCurrentItem`, so a player
        // left at rate 1.0 would play the new item from 0 the moment it's ready, before the resume-seek lands (an
        // audible flash of the start). Pausing here is inert under `.loading`.
        player.pause()

        isPlaying = false
        currentTime = 0
        duration = 0
        isBuffering = false

        // Re-assert .playback on every load (an interruption may have reassigned it). If iOS refuses
        // the session nothing loads: the claim has already shown the error, and play retries.
        guard claimAudioSession() else {
            player.replaceCurrentItem(with: nil)
            prefetchedAsset = nil
            wantsPlayback = false
            onPlaybackStateChanged?()
            return
        }

        status = .loading
        audioError = nil
        pendingSeek = (seekTo.map { $0 > 0 } == true) ? seekTo : nil
        wantsPlayback = autoplay

        let item: AVPlayerItem
        if let warmed = prefetchedAsset, warmed.url == url {
            // Prefetch hit: build the item from the asset whose resource loading
            // already started while the previous track played — skips cold TTFB in the gap.
            item = AVPlayerItem(asset: warmed)
            loadUsedPrefetchedURL = true
            prefetchedAsset = nil
        } else {
            prefetchedAsset = nil
            loadUsedPrefetchedURL = false
            item = AVPlayerItem(url: url)
        }
        player.replaceCurrentItem(with: item)
        setupItemObservers(item: item, generation: myGen)

        // Warmed handoff: the prefetched item may ALREADY be .readyToPlay (or .failed) before
        // the KVO observer attaches, and `.new`-only KVO never fires for a missed transition —
        // autoplay would silently stall. Drive the same handler once against the current status.
        // A cold `AVPlayerItem(url:)` is always `.unknown` here, so this is a no-op on miss.
        if item.status == .readyToPlay || item.status == .failed {
            handleItemStatus(item.status, item: item, generation: myGen)
        }
        updateStallWatchdog()
    }

    // MARK: - Transport

    func play() {
        guard status != .idle, status != .error else { return }
        wantsPlayback = true
        player.play()
        updateStallWatchdog()
    }

    func pause() {
        wantsPlayback = false
        player.pause()
        updateStallWatchdog()
    }

    /// Zero-tolerance seek — no frame drift.
    func seek(to seconds: Double) {
        currentTime = max(0, seconds)  // optimistic: the 1 Hz observer only reports while playing
        let t = CMTime(seconds: max(0, seconds), preferredTimescale: 1000)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Surface an error that originated outside AVFoundation (e.g., no stream ticket available).
    /// Tears down the current item and puts the engine into `.error` state.
    func signalExternalError(_ message: String) {
        teardownItemObservers()
        player.replaceCurrentItem(with: nil)
        prefetchedAsset = nil   // a token-bearing warmed URL must not outlive a dead session
        generation = nextGeneration() // invalidate any in-flight observers
        loadEpoch += 1                // ...and any in-flight play-intent claims
        landedEpoch = loadEpoch
        cancelStallWatchdog()
        status = .error
        audioError = message
        isPlaying = false
        isBuffering = false
        wantsPlayback = false
    }

    /// Fully detach the current item and return to the idle state, so a dead AVPlayerItem is not
    /// left attached to the player. Bumps the generation so any in-flight completions are discarded.
    func clear() {
        teardownItemObservers()
        player.replaceCurrentItem(with: nil)
        prefetchedAsset = nil   // see signalExternalError: no stale token-bearing prefetch
        generation = nextGeneration()
        loadEpoch += 1                // invalidate in-flight play-intent claims
        landedEpoch = loadEpoch
        cancelStallWatchdog()
        status = .idle
        audioError = nil
        isPlaying = false
        isBuffering = false
        wantsPlayback = false
        currentTime = 0
        duration = 0
    }

    // MARK: - Generation

    private func nextGeneration() -> Int {
        generation += 1
        return generation
    }

    // MARK: - deinit

    deinit {
        // nonisolated vars are accessible here without an actor hop.
        timeControlObservation?.invalidate()
        itemStatusObservation?.invalidate()
        durationObservation?.invalidate()
        if let token = endedToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = periodicTimeToken {
            player.removeTimeObserver(token)
        }
        // Session observers.
        if let token = interruptionToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = routeChangeToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
