import Foundation
import os

// MARK: - Advance prefetch
// Fired from `engine.onReady`: resolve and warm the next stream URL (music next, audiobook next file, podcast next
// episode) so the advance neither mints a ticket nor opens a cold connection. Any failure leaves the normal cold load.

#if DEBUG
private let prefetchLog = Logger(subsystem: "com.chevron7locked.kima", category: "engine")
#endif

extension PlaybackController {

    /// Resolve + warm the next stream. Safe to call on every readyToPlay; cheap no-op when
    /// there is no next item or the session is gone. A warm-up that finishes after the player moved on
    /// (a new load, a stop, a sign-out) is dropped, so it can't bring back a cleared stream URL.
    func prefetchNextStream() {
        let epoch = engine.loadEpoch
        switch playbackType {

        case .track:
            // repeat-one advances by looping the CURRENT item (no reload) — nothing to warm.
            guard repeatMode != .one, !queue.isEmpty else { return }
            let (nextIdx, _) = computeNext()
            guard let nextIdx, queue.indices.contains(nextIdx) else { return }
            let track = queue[nextIdx]
            warmNextStream(epoch: epoch, logLabel: "track idx=\(nextIdx)") { source in
                await source.playableURL(trackId: track.id)
            }

        case .audiobook(let session):
            // Last file finishing = book done — nothing to warm.
            guard let currentFile = session.fileByIndex(currentLongFormFileIndex),
                  !session.isLastFile(currentFile),
                  let nextFile = session.nextFile(after: currentFile) else { return }
            warmNextStream(epoch: epoch, logLabel: "book file=\(nextFile.index)") { source in
                await source.playableURL(bookId: session.bookId, index: nextFile.index)
            }

        case .podcastEpisode(let podcastId, let episode, let episodeQueue):
            // A sample plays nothing after it.
            guard podcastSampleItunesId == nil else { return }
            // Warm what the episode's end will play: the server's next episode, or with no answer the list's next row.
            let lookup = nextEpisodeLookup(podcastId: podcastId, episodeId: episode.id)
            Task { @MainActor [weak self] in
                let answer = await lookup.value
                guard let self, self.engine.isCurrentLoad(epoch) else { return }
                let nextEpisode: Episode
                switch answer {
                case .next(let next):
                    nextEpisode = next
                case .endOfShow:
                    return
                case .unknown:
                    guard let idx = episodeQueue.firstIndex(where: { $0.id == episode.id }),
                          episodeQueue.indices.contains(idx + 1) else { return }
                    nextEpisode = episodeQueue[idx + 1]
                }
                self.warmNextStream(epoch: epoch, logLabel: "episode \(nextEpisode.id)") { source in
                    await source.playableURL(podcastId: podcastId, episodeId: nextEpisode.id)
                }
            }
        }
    }

    /// Asks the stream source for the next stream's playable URL, then warms it unless the player
    /// moved on (epoch changed) meanwhile.
    private func warmNextStream(epoch: Int, logLabel: String,
                                ask: @escaping @MainActor (StreamSource) async -> StreamSource.Answer) {
        Task { @MainActor [weak self] in
            guard let self, let source = self.streamSource else { return }
            guard case .url(let url) = await ask(source), self.engine.isCurrentLoad(epoch)
            else { return }   // no answer, or a URL the login can't be blamed for — prefetching is opportunistic
            #if DEBUG
            prefetchLog.info("KIMA_AUDIO prefetch \(logLabel, privacy: .public)")
            #endif
            self.engine.prepareStream(url: url)
        }
    }
}
