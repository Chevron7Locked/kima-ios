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

    // MARK: - Loaders

    /// `prepare` runs before the playable-URL ask (see `loadStream`). The file is chosen from
    /// `bookTime()` at the call. When that is the file already loaded, `bookTime()` is read again
    /// when the load is issued, so a skip within the file made during the ticket fetch is where it
    /// starts (a skip to another file claims its own load). When the file changes, the start is
    /// fixed at the call: `recoveryPoint` reads the engine's time against the current file, and the
    /// engine's time still belongs to the old one.
    func loadBookPosition(bookTime: @escaping @MainActor () -> Double, session: BookSession, autoplay: Bool,
                          prepare: (@MainActor () async -> Void)? = nil) {
        let (file, fileTime) = session.locate(bookTime: bookTime())
        let seekTo: @MainActor () -> Double? = file.index == currentLongFormFileIndex
            ? { session.fileTime(bookTime: bookTime(), in: file) }
            : { fileTime }
        currentLongFormFileIndex = file.index  // track in-flight file before the async hop
        let posClaim = engine.claimLoad()  // staleness guard — see loadCurrentTrack
        loadStream(claim: posClaim, autoplay: autoplay, seekTo: seekTo, prepare: prepare) { source in
            await source.playableURL(bookId: session.bookId, index: file.index)
        }
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
        case .audiobook(let session):
            loadBookPosition(bookTime: position, session: session, autoplay: autoplay, prepare: prepare)
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
