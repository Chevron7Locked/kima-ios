import AVFoundation
import UIKit

// MARK: - Long-form helpers
//
// Session building, stream loaders, the progress timer and the resign observer for long-form playback.

extension PlaybackController {

    // MARK: - BookSession builder

    func makeBookSession(audiobook: Audiobook, client: KimaAPIClient) async -> BookSession? {
        // Case 1: tracks already embedded in the response.
        if let tracks = audiobook.tracks, !tracks.isEmpty {
            return BookSession(
                bookId: audiobook.id,
                totalDuration: audiobook.duration,
                files: tracks.sorted { $0.startOffset < $1.startOffset }
            )
        }
        // Case 2: synthesize single-file session.
        if audiobook.trackCount == nil || audiobook.trackCount == 0 || audiobook.trackCount == 1 {
            let synth = AudiobookTrack(index: 1, startOffset: 0, duration: audiobook.duration)
            return BookSession(bookId: audiobook.id, totalDuration: audiobook.duration, files: [synth])
        }
        // Case 3: fetch full detail to get tracks.
        do {
            let full = try await client.getAudiobook(id: audiobook.id)
            if let tracks = full.tracks, !tracks.isEmpty {
                return BookSession(
                    bookId: full.id,
                    totalDuration: full.duration,
                    files: tracks.sorted { $0.startOffset < $1.startOffset }
                )
            }
            // Fallback single-file after fetch.
            let synth = AudiobookTrack(index: 1, startOffset: 0, duration: full.duration)
            return BookSession(bookId: full.id, totalDuration: full.duration, files: [synth])
        } catch {
            playerNotice = "couldn't open this audiobook. check your connection and try again."
            return nil
        }
    }

    // MARK: - The audiobook's loaded file

    /// Run `change` on the playing audiobook's session and return its value with the session after
    /// it. Nil when no audiobook is playing. The loaded file is the session's one mutable state, so
    /// `playbackType` is written back only when it moved: a seek within the file leaves the observed
    /// value alone, while a file change re-notifies its readers (CarPlay's `configure` re-runs,
    /// idempotent, as it does on every podcast episode change).
    @discardableResult
    func updateBook<Value>(_ change: (inout BookSession) -> Value) -> (value: Value, session: BookSession)? {
        guard case .audiobook(var session) = playbackType else { return nil }
        let before = session.loadedFileIndex
        let value = change(&session)
        if session.loadedFileIndex != before { playbackType = .audiobook(session) }
        return (value, session)
    }

    /// Stream `file` of `session`'s book: the one shape of every audiobook file load. `seekTo` is
    /// read when the load is issued (see `loadStream`); nil starts at the file's top.
    func loadBookFile(_ file: AudiobookTrack, of session: BookSession, autoplay: Bool,
                      seekTo: @escaping @MainActor () -> Double?,
                      prepare: (@MainActor () async -> Void)? = nil,
                      afterLoad: (@MainActor () -> Void)? = nil) {
        let claim = engine.claimLoad()  // staleness guard — see loadCurrentTrack
        loadStream(claim: claim, autoplay: autoplay, seekTo: seekTo, prepare: prepare,
                   afterLoad: afterLoad) { source in
            await source.playableURL(bookId: session.bookId, index: file.index)
        }
    }

    // MARK: - Loaders

    /// Load the playing audiobook at `bookTime()`. `prepare` runs before the playable-URL ask (see
    /// `loadStream`). The file is chosen from `bookTime()` at the call. When that is the file
    /// already loaded, `bookTime()` is read again when the load is issued, so a skip within the file
    /// made during the ticket fetch is where it starts (a skip to another file claims its own load).
    /// When the file changes, the start is fixed at the call: `recoveryPoint` reads the engine's time
    /// against the loaded file, and the engine's time still belongs to the old one.
    func loadBookPosition(bookTime: @escaping @MainActor () -> Double, autoplay: Bool,
                          prepare: (@MainActor () async -> Void)? = nil) {
        // The session's loaded file moves here, before the async hop: the file in flight is the loaded one.
        guard let (load, session) = updateBook({ $0.load(at: bookTime()) }) else { return }
        let file = load.file
        let seekTo: @MainActor () -> Double? = load.isSameFile
            ? { session.fileTime(bookTime: bookTime(), in: file) }
            : { load.fileTime }
        loadBookFile(file, of: session, autoplay: autoplay, seekTo: seekTo, prepare: prepare)
    }

    /// `seekTo` is read when the load is issued (see `loadStream`).
    func loadPodcastEpisode(
        podcastId: String, episode: Episode, seekTo: @escaping @MainActor () -> Double?, autoplay: Bool,
        prepare: (@MainActor () async -> Void)? = nil
    ) {
        let sampleItunesId = podcastSampleItunesId  // read before the async hop: a sample streams its snippet
        let epClaim = engine.claimLoad()  // staleness guard — see loadCurrentTrack
        loadStream(claim: epClaim, autoplay: autoplay,
                   seekTo: seekTo, prepare: prepare) { source in
            if let sampleItunesId {
                return await source.playableURL(sampleItunesId: sampleItunesId)
            }
            return await source.playableURL(podcastId: podcastId, episodeId: episode.id)
        }
    }

    /// The last file ended. The finished save goes after any save already on its way, and later
    /// saves of this book stop, so the pause here can't save it as unfinished.
    func finishAudiobook(session: BookSession) {
        finishedLongFormId = session.bookId
        lastSavedProgressTime = session.totalDuration
        engine.pause()
        let client = longFormAPIClient
        enqueueProgressSave {
            _ = try? await client?.saveAudiobookProgress(
                bookId: session.bookId,
                currentTime: session.totalDuration,
                duration: session.totalDuration,
                isFinished: true
            )
        }
        nowPlayingHook?()
    }

    /// Rebuild the current audiobook/podcast stream at `position()`: seconds into the episode, or
    /// into the whole book. It is read when the load is issued (an audiobook's file is chosen at the
    /// call; see `loadBookPosition`). `autoplay` respects the play intent at the moment of failure —
    /// a PAUSED long-form item whose connection dropped must come back paused at position, not auto-resume.
    func rebuildLongFormStream(at position: @escaping @MainActor () -> Double, autoplay: Bool = true,
                               prepare: (@MainActor () async -> Void)? = nil) {
        switch playbackType {
        case .audiobook:
            loadBookPosition(bookTime: position, autoplay: autoplay, prepare: prepare)
        case .podcastEpisode(let podcastId, let episode, _):
            loadPodcastEpisode(podcastId: podcastId, episode: episode, seekTo: position,
                               autoplay: autoplay, prepare: prepare)
        case .track:
            break
        }
    }

    // MARK: - Timer + resign observer

    func startProgressTimer() {
        progressTimerTask?.cancel()
        progressTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { return }
                guard self.engine.isPlaying else { continue }
                self.saveProgress()
            }
        }
    }

    func startResignObserver() {
        if let existing = progressResignToken {
            NotificationCenter.default.removeObserver(existing)
        }
        progressResignToken = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.saveProgress() }
        }
    }
}
