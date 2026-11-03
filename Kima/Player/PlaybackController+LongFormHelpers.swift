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

    /// `prepare` runs before the ticket fetch (see `loadStream`).
    func loadBookPosition(bookTime: Double, session: BookSession, autoplay: Bool,
                          prepare: (@MainActor () async -> Void)? = nil) {
        let (file, fileTime) = session.locate(bookTime: bookTime)
        currentLongFormFileIndex = file.index  // track in-flight file before the async hop
        let client = longFormAPIClient
        let posClaim = engine.claimLoad()  // staleness guard — see loadCurrentTrack
        loadStream(claim: posClaim, client: client, autoplay: autoplay,
                   seekTo: fileTime > 0 ? fileTime : nil, prepare: prepare) { [weak self] token in
            guard let self else { return nil }
            return StreamURL.audiobook(base: self.server, bookId: session.bookId, index: file.index, token: token)
        }
    }

    func loadPodcastEpisode(
        podcastId: String, episode: Episode, seekTo: Double, autoplay: Bool,
        prepare: (@MainActor () async -> Void)? = nil
    ) {
        let client = longFormAPIClient
        let epClaim = engine.claimLoad()  // staleness guard — see loadCurrentTrack
        loadStream(claim: epClaim, client: client, autoplay: autoplay,
                   seekTo: seekTo > 0 ? seekTo : nil, prepare: prepare) { [weak self] token in
            guard let self else { return nil }
            if let itunesId = self.podcastSampleItunesId {
                return StreamURL.podcastSnippet(base: self.server, itunesId: itunesId, token: token)
            }
            return StreamURL.podcastEpisode(base: self.server, podcastId: podcastId, episodeId: episode.id, token: token)
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

    /// Rebuild the current audiobook/podcast stream at `bookTime`. `autoplay` respects the play
    /// intent at the moment of failure — a PAUSED long-form item whose connection dropped must
    /// come back paused at position, not auto-resume.
    func rebuildLongFormStream(at bookTime: Double, autoplay: Bool = true,
                               prepare: (@MainActor () async -> Void)? = nil) {
        switch playbackType {
        case .audiobook(let session):
            loadBookPosition(bookTime: bookTime, session: session, autoplay: autoplay, prepare: prepare)
        case .podcastEpisode(let podcastId, let episode, _):
            loadPodcastEpisode(podcastId: podcastId, episode: episode, seekTo: bookTime,
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
