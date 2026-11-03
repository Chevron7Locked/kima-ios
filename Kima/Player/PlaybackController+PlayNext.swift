import Foundation

// MARK: - Play Next
// Inserts a track right after whatever is playing; idle player or audiobook / podcast starts a music session.
// Shuffle: splice a fresh permutation around the current track; an index-splice would be wrong because
// `shufflePosition + 1` is an unrelated track. The caller gets the outcome back (this class is toast-free).

/// What "play next" or "add to queue" actually did, so the calling view can say so.
enum QueueAddOutcome: Equatable, Sendable {
    case added             // landed in the queue (play next: right after the current track)
    case startedIdle       // nothing was playing — playback began
    case stoppedAudiobook  // an audiobook was playing — it stopped and the music began
    case stoppedPodcast    // a podcast was playing — it stopped and the music began
}

extension PlaybackController {

    /// Plays `track` immediately after whatever is playing now.
    @discardableResult
    func playNext(_ track: Track) -> QueueAddOutcome { playNext(contentsOf: [track]) }

    /// Batch variant used by drag-and-drop (whole sections can be dragged at once).
    /// Inserted tracks keep the given order.
    @discardableResult
    func playNext(contentsOf tracks: [Track]) -> QueueAddOutcome {
        guard !tracks.isEmpty else { return .added }
        if let started = startInsteadOfAdding(tracks, shuffle: nil) { return started }

        let anchor = playingQueueIndex ?? min(currentIndex, queue.count - 1)
        let insertAt = min(anchor + 1, queue.count)
        queue.insert(contentsOf: tracks, at: insertAt)
        if isShuffle {
            let inserted = Array(insertAt..<(insertAt + tracks.count))
            rebuildShuffleOrder(afterPlayNextInserting: inserted)
        }
        nowPlayingHook?()
        syncHook?()
        return .added
    }

    /// With no music queue to add to, start `tracks` as a new music session and say what happened:
    /// an idle player starts; an audiobook or podcast stops (web parity — their queue is empty, so
    /// adding replaces them). Nil when there is a music queue to add to.
    func startInsteadOfAdding(_ tracks: [Track], shuffle: Bool?) -> QueueAddOutcome? {
        let outcome: QueueAddOutcome
        switch playbackType {
        case .audiobook:       outcome = .stoppedAudiobook
        case .podcastEpisode:  outcome = .stoppedPodcast
        case .track:
            guard queue.isEmpty else { return nil }
            outcome = .startedIdle
        }
        play(tracks: tracks, startAt: 0, shuffle: shuffle)
        return outcome
    }

    /// The queue index of the track the next advance will play (see file header).
    private var playingQueueIndex: Int? {
        if isShuffle {
            guard shuffleOrder.indices.contains(shufflePosition) else { return nil }
            return shuffleOrder[shufflePosition]
        }
        return queue.indices.contains(currentIndex) ? currentIndex : nil
    }

    /// Rebuild the shuffle permutation after a play-next insert and drag the inserted
    /// indices to sit immediately after the current track. Positions are preserved:
    /// `buildShuffleOrder` prepends the current index (order[0] == current, parity with
    /// play()), so shufflePosition returns to 0 and the playing track never moves.
    private func rebuildShuffleOrder(afterPlayNextInserting inserted: [Int]) {
        let currentQueue = playingQueueIndex ?? min(currentIndex, queue.count - 1)
        var order = buildShuffleOrder(keeping: currentQueue, total: queue.count)
        let insertedSet = Set(inserted)
        // Pull the inserted entries (the fresh permutation scattered them randomly) …
        let pulled = order.filter { insertedSet.contains($0) }
        order.removeAll { insertedSet.contains($0) }
        // … and re-insert them right after the current track (order[0]).
        order.insert(contentsOf: pulled, at: 1)
        shuffleOrder = order
        shufflePosition = 0
    }
}
