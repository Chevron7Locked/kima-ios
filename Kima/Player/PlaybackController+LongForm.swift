import AVFoundation
import UIKit
import os

// MARK: - Long-form playback (audiobooks + podcasts)
// Progress saves every 15 s while playing and on pause, background, interruption and end; skipped when
// |currentTime − lastSavedProgressTime| ≤ 0.5 s. Failure recovery is the music rebuild-at-position path (+Recovery).

extension PlaybackController {

    // MARK: - Audiobook entry point

    /// Begin playing an audiobook, fetching tracks from the server when not embedded. Resumes from
    /// `audiobook.progress?.currentTime`; `resumeAt` overrides it when the caller already knows the position
    /// (e.g. CarPlay's Continue list), so a fetched `progress` that comes back nil can't restart the book at 0.
    func playAudiobook(_ audiobook: Audiobook, client: KimaAPIClient, resumeAt: Double? = nil) async {
        guard let session = await makeBookSession(audiobook: audiobook, client: client) else { return }

        cancelSkipDebounce()
        stopLongForm()   // cancel any running session (progress timer, resign observer)

        queue          = []
        playbackType   = .audiobook(session)
        longFormAPIClient   = client
        longFormNowPlayingMeta = LongFormNowPlayingMeta(
            title: audiobook.title, artist: audiobook.author,
            coverURL: longFormCoverURL(audiobook.coverUrl)
        )

        let resumeTime = resumeAt ?? audiobook.progress?.currentTime ?? 0
        lastSavedProgressTime = resumeTime

        engine.claimAudioSession(mode: .spokenAudio)
        loadBookPosition(bookTime: resumeTime, session: session, autoplay: true)

        startProgressTimer()
        startResignObserver()
        nowPlayingHook?()
    }

    // MARK: - Podcast entry point

    /// Begin playing a podcast episode. `queue` is the full sorted episode list so
    /// auto-advance works at end-of-episode. Resumes from `episode.progress?.currentTime`.
    func playPodcastEpisode(
        _ episode: Episode,
        podcast: Podcast,
        queue episodeQueue: [Episode],
        client: KimaAPIClient
    ) {
        cancelSkipDebounce()
        stopLongForm()

        queue        = []
        playbackType = .podcastEpisode(podcastId: podcast.id, episode: episode, queue: episodeQueue)
        longFormAPIClient   = client
        longFormNowPlayingMeta = LongFormNowPlayingMeta(
            title: episode.title, artist: podcast.title,
            coverURL: longFormCoverURL(episode.imageUrl ?? podcast.coverUrl)
        )

        let resumeTime = episode.progress?.currentTime ?? 0
        lastSavedProgressTime = resumeTime

        engine.claimAudioSession(mode: .spokenAudio)
        loadPodcastEpisode(podcastId: podcast.id, episode: episode, seekTo: resumeTime, autoplay: true)

        startProgressTimer()
        startResignObserver()
        nowPlayingHook?()
    }

    // MARK: - Session teardown (called before switching content or back to music)

    /// Live-refresh the episode queue of an active `.podcastEpisode` session after the detail
    /// VM pages in more episodes. Auto-advance walks the queue snapshot captured at tap time;
    /// without this refresh continuous play silently stops at the first page boundary.
    /// No-op unless an episode of this podcast is currently active.
    func updatePodcastQueue(podcastId: String, episodes: [Episode]) {
        guard case .podcastEpisode(let pid, let current, _) = playbackType, pid == podcastId else { return }
        playbackType = .podcastEpisode(podcastId: pid, episode: current, queue: episodes)
    }

    /// Cancel the progress timer, remove the resign observer, and reset long-form state.
    /// Called from `playAudiobook`, `playPodcastEpisode`, and `PlaybackController.play(tracks:)`.
    func stopLongForm() {
        progressTimerTask?.cancel()
        progressTimerTask = nil

        if let token = progressResignToken {
            NotificationCenter.default.removeObserver(token)
            progressResignToken = nil
        }

        // Don't reset playbackType here — caller sets it immediately after.
        // We DO clear the API client reference to prevent phantom saves after teardown.
        longFormAPIClient = nil
        finishedLongFormId = nil
        podcastSampleItunesId = nil
        endStation()
        resetRecoveryBudget()   // new content starts with a full recovery budget
    }

    // MARK: - Speed control (§4.3)

    /// Set the playback rate for the current long-form type and persist in UserDefaults.
    /// Applies immediately when the engine is playing or buffering.
    func setLongFormSpeed(_ rate: Float) {
        switch playbackType {
        case .audiobook:
            audiobookSpeed = rate
            UserDefaults.standard.set(rate, forKey: "kima.speed.audiobook")
        case .podcastEpisode:
            podcastSpeed = rate
            UserDefaults.standard.set(rate, forKey: "kima.speed.podcast")
        case .track:
            return
        }
        // Apply immediately if the engine is running (rate > 0 starts/continues play).
        if engine.isPlaying || engine.status == .buffering {
            engine.player.rate = rate
        }
        // Re-push now-playing so CarPlay's rate button (and the lock screen) reflect a
        // phone-initiated speed change immediately — symmetric with CarPlayNowPlaying.cycleSpeed,
        // which drives the same call from the CarPlay side.
        nowPlayingHook?()
    }

    // MARK: - Cover art resolution

    /// Resolve a `coverUrl`/`imageUrl` string (relative library path, opaque hash id, or an
    /// absolute URL that `CoverArtURL` proxies) into a ready-to-use cover art URL. Mirrors the
    /// nil/empty guard `CoverArtImage.coverURL` uses so callers can pass an optional straight
    /// through (e.g. `episode.imageUrl ?? podcast.coverUrl`).
    func longFormCoverURL(_ coverId: String?, size: Int = 512) -> URL? {
        guard let coverId, !coverId.isEmpty else { return nil }
        return CoverArtURL.url(base: server, coverId: coverId, size: size)
    }

    // MARK: - File-aware seek (long-form override of engine.seek, called by PlaybackController.seek)

    /// Perform a seek to `seconds` (book-absolute for audiobooks, episode-absolute for podcasts).
    /// For audiobooks, crossing a file boundary triggers a file reload. Does NOT cancel the
    /// skip debounce (callers do that before invoking this).
    func performSeekInternal(to seconds: Double) {
        // Play reporting: a seek breaks the chain of deltas rather than producing
        // one enormous one.
        playMeter.breakChain()
        finishedLongFormId = nil   // seeking in a finished book or episode means listening again
        switch playbackType {
        case .audiobook(let session):
            let (file, fileTime) = session.locate(bookTime: seconds)
            if file.index != currentLongFormFileIndex {
                // Cross-file seek — reload the new file at fileTime.
                currentLongFormFileIndex = file.index
                let shouldAutoplay = engine.isPlaying || engine.status == .buffering
                let client = longFormAPIClient
                let seekClaim = engine.claimLoad()  // staleness guard — see loadCurrentTrack
                loadStream(claim: seekClaim, client: client, autoplay: shouldAutoplay,
                           seekTo: fileTime > 0 ? fileTime : nil) { [weak self] token in
                    guard let self else { return nil }
                    return StreamURL.audiobook(base: self.server, bookId: session.bookId, index: file.index, token: token)
                }
            } else {
                engine.seek(to: fileTime)
            }
        case .podcastEpisode, .track:
            engine.seek(to: seconds)
        }
    }


    // MARK: - Progress saving

    /// Save the current playback position to the server.
    /// Dedup guard: skipped when |currentTime − lastSavedProgressTime| ≤ 0.5 s.
    /// Thread: @MainActor (inherited from PlaybackController).
    func saveProgress() {
        guard let client = longFormAPIClient, podcastSampleItunesId == nil else { return }
        // Mid-load engine time is 0; saving it would overwrite the real position.
        guard [.playing, .paused, .buffering, .blocked].contains(engine.status) else { return }
        // A load is on its way: the engine's time still belongs to the previous file or episode.
        guard !engine.isLoadPending else { return }
        // A finished book or episode stays finished until the user seeks in it again.
        guard finishedLongFormId == nil || finishedLongFormId != nowPlayingItemId else { return }

        switch playbackType {
        case .track:
            return  // music progress goes through PlaybackSyncCoordinator

        case .audiobook(let session):
            guard let file = session.fileByIndex(currentLongFormFileIndex) else { return }
            let bookTime = file.startOffset + engine.currentTime
            guard abs(bookTime - lastSavedProgressTime) > 0.5 else { return }
            lastSavedProgressTime = bookTime
            enqueueProgressSave {
                _ = try? await client.saveAudiobookProgress(
                    bookId: session.bookId,
                    currentTime: bookTime,
                    duration: session.totalDuration,
                    isFinished: false
                )
            }

        case .podcastEpisode(let podcastId, let episode, _):
            let t = engine.currentTime
            guard abs(t - lastSavedProgressTime) > 0.5 else { return }
            lastSavedProgressTime = t
            enqueueProgressSave {
                _ = try? await client.saveEpisodeProgress(
                    podcastId: podcastId, episodeId: episode.id,
                    currentTime: t, duration: episode.duration, isFinished: false
                )
            }
        }
    }

    /// Send one progress save once every earlier one has finished, so an older position can't
    /// reach the server after a newer one (or after "finished").
    func enqueueProgressSave(_ send: @escaping @Sendable () async -> Void) {
        let previous = progressSaveChain
        progressSaveChain = Task {
            await previous?.value
            await send()
        }
    }

}
