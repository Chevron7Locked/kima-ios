import Foundation
import UIKit

// MARK: - Long-form ended handling (failures share the music recovery in +Recovery)

/// What plays after a podcast episode, as the server answered.
enum PodcastNextAnswer: Sendable {
    /// The show's next episode this listener has not finished.
    case next(Episode)
    /// Nothing after it.
    case endOfShow
    /// No answer: offline or an error.
    case unknown

    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

/// One ask of GET /podcasts/:podcastId/episodes/:episodeId/next.
@MainActor
final class PodcastNextLookup {
    let episodeId: String
    let task: Task<PodcastNextAnswer, Never>
    private let askedAt = Date()
    /// The answer, once it has come.
    private(set) var answer: PodcastNextAnswer?

    init(podcastId: String, episodeId: String, client: KimaAPIClient?) {
        self.episodeId = episodeId
        task = Task {
            guard let client,
                  let answer = try? await client.getNextEpisode(podcastId: podcastId, episodeId: episodeId)
            else { return .unknown }
            guard let next = answer.episode?.asEpisode, next.id != episodeId else { return .endOfShow }
            return .next(next)
        }
        Task { [weak self, task] in
            let answer = await task.value
            self?.answer = answer
        }
    }

    /// The ask failed (offline, an error): worth asking again.
    var failed: Bool {
        if case .unknown? = answer { return true }
        return false
    }

    /// Asked in the last ten minutes. An older answer may be out of date: the listener can finish episodes on
    /// another device meanwhile.
    var isFresh: Bool { Date().timeIntervalSince(askedAt) < 600 }
}

/// Resumes a continuation with the first answer given; later ones are dropped. Used only on the main actor.
private final class ResumeOnce: @unchecked Sendable {
    private var continuation: CheckedContinuation<PodcastNextAnswer?, Never>?
    init(_ continuation: CheckedContinuation<PodcastNextAnswer?, Never>) { self.continuation = continuation }
    func resume(_ answer: PodcastNextAnswer?) {
        continuation?.resume(returning: answer)
        continuation = nil
    }
}

extension PlaybackController {

    // MARK: - Ended handlers (called from handleEnded() in +Queue.swift)

    /// Called when the current audiobook file finishes.
    func handleAudiobookFileEnded(autoplay: Bool = true) {
        guard case .audiobook(let session) = playbackType else { return }
        guard let currentFile = session.fileByIndex(currentLongFormFileIndex) else {
            finishAudiobook(session: session)
            return
        }

        if session.isLastFile(currentFile) {
            finishAudiobook(session: session)
        } else if let nextFile = session.nextFile(after: currentFile) {
            currentLongFormFileIndex = nextFile.index
            let client = longFormAPIClient
            let endClaim = engine.claimLoad()  // staleness guard — see loadCurrentTrack
            loadStream(claim: endClaim, client: client, autoplay: autoplay, seekTo: nil,
                       afterLoad: { [weak self] in self?.nowPlayingHook?() }) { [weak self] token in
                guard let self else { return nil }
                return StreamURL.audiobook(base: self.server, bookId: session.bookId, index: nextFile.index, token: token)
            }
        }
    }

    /// Called when the current podcast episode finishes. Plays what the server says comes next: the show's next
    /// episode by release date that this listener has not finished, or nothing at the end of the show. The answer
    /// asked when the episode became ready is used when it is recent; otherwise it asks now. With no answer within
    /// `podcastNextDeadline` (offline, an error, a slow server) it plays an older answer if there is one, else the
    /// next row of the list playback started from; a slow answer that lands soon after moves to the episode it names.
    func handlePodcastEpisodeEnded(autoplay: Bool = true) {
        guard case .podcastEpisode(let podcastId, let episode, let queue) = playbackType else { return }

        // A sample of a show not followed: nothing to save and nothing after it.
        if podcastSampleItunesId != nil {
            pauseAtPodcastQueueEnd()
            return
        }

        // Save the finished episode, after any save already on its way; later saves skip it.
        finishedLongFormId = episode.id
        let client = longFormAPIClient
        enqueueProgressSave {
            _ = try? await client?.saveEpisodeProgress(
                podcastId: podcastId, episodeId: episode.id,
                currentTime: episode.duration, duration: episode.duration, isFinished: true
            )
        }

        // The answer asked when the episode became ready, if any; the server's next episode does not depend on this
        // one being saved as finished, so nothing waits on the save.
        let early = podcastNextLookup?.episodeId == episode.id ? podcastNextLookup : nil
        podcastNextLookup = nil
        let epoch = engine.loadEpoch
        let deadline = podcastNextDeadline
        // Keeps the app running in the background while it picks the next episode and starts loading it, since the
        // episode that kept it awake has ended.
        let background = UIApplication.shared.beginBackgroundTask(withName: "next episode")
        Task { @MainActor [weak self] in
            defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
            guard let self else { return }
            var answer: PodcastNextAnswer?
            // An ask still on its way when the deadline passes; its answer can still arrive.
            var pending: Task<PodcastNextAnswer, Never>?
            if let early, early.isFresh, !early.failed {
                answer = await Self.answer(of: early.task, within: deadline)
                if answer == nil { pending = early.task }   // too slow: no second wait
            }
            if pending == nil, answer == nil || answer?.isUnknown == true {
                let lookup = PodcastNextLookup(podcastId: podcastId, episodeId: episode.id, client: client)
                answer = await Self.answer(of: lookup.task, within: deadline)
                if answer == nil { pending = lookup.task }
                // No answer now: an older one, if it was an answer, beats the list.
                if answer == nil || answer?.isUnknown == true, let old = early?.answer, !old.isUnknown { answer = old }
            }
            // The user may have started something else while the answer loaded.
            guard self.isStillPlaying(episode.id, of: podcastId, epoch: epoch) else { return }
            switch answer ?? .unknown {
            case .unknown:
                // Offline, an error, or too slow: the next row of the list playback started from.
                await self.advanceFromQueue(podcastId: podcastId, episode: episode, queue: queue,
                                            epoch: epoch, autoplay: autoplay)
                if let pending { self.followLateAnswer(pending, podcastId: podcastId, autoplay: autoplay) }
            case .endOfShow:
                self.pauseAtPodcastQueueEnd()
            case .next(let next):
                let rest = queue.contains { $0.id == next.id } ? queue : queue + [next]
                self.advancePodcastEpisode(podcastId: podcastId, nextEpisode: next, queue: rest, autoplay: autoplay)
            }
        }
    }

    /// The server's answer for what plays after `episodeId`: the one already asked for it, or a new ask. Asked when
    /// an episode becomes ready, so its end (and the next stream's warm-up) has it without a round trip.
    /// A failed or old ask is asked again.
    func nextEpisodeLookup(podcastId: String, episodeId: String) -> Task<PodcastNextAnswer, Never> {
        if let lookup = podcastNextLookup, lookup.episodeId == episodeId, lookup.isFresh, !lookup.failed {
            return lookup.task
        }
        let lookup = PodcastNextLookup(podcastId: podcastId, episodeId: episodeId, client: longFormAPIClient)
        podcastNextLookup = lookup
        return lookup.task
    }

    /// `lookup`'s answer, or nil when `deadline` passes first.
    private static func answer(of lookup: Task<PodcastNextAnswer, Never>,
                               within deadline: Duration) async -> PodcastNextAnswer? {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task { @MainActor in once.resume(await lookup.value) }
            Task { @MainActor in
                try? await Task.sleep(for: deadline)
                once.resume(nil)
            }
        }
    }

    /// After a too-slow answer sent playback to the list's next row: when the answer lands within 20 seconds and
    /// names another episode, and that row is still loading or just started (same load, nothing else chosen), play
    /// the server's choice instead.
    private func followLateAnswer(_ lookup: Task<PodcastNextAnswer, Never>, podcastId: String, autoplay: Bool) {
        guard case .podcastEpisode(_, let fallback, let queue) = playbackType else { return }
        let epoch = engine.loadEpoch
        let startedAt = Date()
        Task { @MainActor [weak self] in
            guard case .next(let next) = await lookup.value, let self, next.id != fallback.id,
                  Date().timeIntervalSince(startedAt) < 20, self.engine.isCurrentLoad(epoch),
                  case .podcastEpisode(let pid, let current, _) = self.playbackType,
                  pid == podcastId, current.id == fallback.id else { return }
            let rest = queue.contains { $0.id == next.id } ? queue : queue + [next]
            self.advancePodcastEpisode(podcastId: podcastId, nextEpisode: next, queue: rest, autoplay: autoplay)
        }
    }

    /// The finished episode is still the one in the player and the listener has not started it again (a seek
    /// clears `finishedLongFormId`).
    private func isStillPlaying(_ episodeId: String, of podcastId: String, epoch: Int) -> Bool {
        guard engine.isCurrentLoad(epoch), finishedLongFormId == episodeId,
              case .podcastEpisode(let pid, let current, _) = playbackType else { return false }
        return pid == podcastId && current.id == episodeId
    }

    /// The offline fallback: the next row of the list playback started from. When that list runs out and it runs
    /// newest-first (ISO-8601 strings compare lexicographically), fetch the next server page before pausing.
    private func advanceFromQueue(podcastId: String, episode: Episode, queue: [Episode], epoch: Int, autoplay: Bool) async {
        if let idx = queue.firstIndex(where: { $0.id == episode.id }), queue.indices.contains(idx + 1) {
            advancePodcastEpisode(podcastId: podcastId, nextEpisode: queue[idx + 1], queue: queue, autoplay: autoplay)
            return
        }
        var page: EpisodePage?
        if let client = longFormAPIClient, queue.count >= 2, queue[0].publishedAt >= queue[1].publishedAt {
            page = try? await client.getPodcastEpisodesPage(id: podcastId, limit: 200, offset: queue.count)
        }
        guard isStillPlaying(episode.id, of: podcastId, epoch: epoch) else { return }
        let known = Set(queue.map(\.id))
        let grown = queue + (page?.episodes ?? []).filter { !known.contains($0.id) }
        guard let idx = grown.firstIndex(where: { $0.id == episode.id }), grown.indices.contains(idx + 1) else {
            pauseAtPodcastQueueEnd()
            return
        }
        advancePodcastEpisode(podcastId: podcastId, nextEpisode: grown[idx + 1], queue: grown, autoplay: autoplay)
    }

    /// Pause cleanly at the true end of the episode queue (last-episode state preserved).
    private func pauseAtPodcastQueueEnd() {
        engine.pause()
        nowPlayingHook?()
    }

    /// Shared continuous-play tail: switch playback to `nextEpisode` within `queue`.
    private func advancePodcastEpisode(podcastId: String, nextEpisode: Episode, queue: [Episode], autoplay: Bool) {
        lastSavedProgressTime = nextEpisode.progress?.currentTime ?? 0

        playbackType = .podcastEpisode(podcastId: podcastId, episode: nextEpisode, queue: queue)
        longFormNowPlayingMeta = LongFormNowPlayingMeta(
            title: nextEpisode.title,
            artist: longFormNowPlayingMeta?.artist ?? "",
            // No Podcast object in scope here (only podcastId) — prefer the next episode's own
            // art; fall back to the just-finished episode's meta so the cover doesn't blank out
            // when neither episode carries per-episode art (it was resolved from the podcast's
            // cover at playPodcastEpisode(), so this carries that forward correctly).
            coverURL: longFormCoverURL(nextEpisode.imageUrl) ?? longFormNowPlayingMeta?.coverURL
        )

        let resumeTime = nextEpisode.progress?.currentTime ?? 0
        loadPodcastEpisode(podcastId: podcastId, episode: nextEpisode, seekTo: resumeTime, autoplay: autoplay)
        nowPlayingHook?()
    }
}
