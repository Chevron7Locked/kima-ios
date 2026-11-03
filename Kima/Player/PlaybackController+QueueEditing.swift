import Foundation

// MARK: - Enqueue, shuffle-order build, and queue-mutation logic
//
// Navigation + end/fail handling (previous/next/handleEnded/handleFailed) lives in
// PlaybackController+Queue.swift.

extension PlaybackController {

    // MARK: - Enqueue (Add to Queue)

    /// Append a single track to the end of the current queue (see `enqueue(tracks:)`).
    @discardableResult
    func enqueue(track: Track) -> QueueAddOutcome {
        enqueue(tracks: [track])
    }

    /// Append an ordered list of tracks to the end of the current queue, leaving current
    /// playback untouched. With nothing loaded, or during an audiobook or podcast, the tracks
    /// start playing instead (`startInsteadOfAdding`); the outcome says which, for the toast.
    @discardableResult
    func enqueue(tracks: [Track]) -> QueueAddOutcome {
        guard !tracks.isEmpty else { return .added }
        if let started = startInsteadOfAdding(tracks, shuffle: false) { return started }
        let firstNew = queue.count
        queue.append(contentsOf: tracks)
        if isShuffle { shuffleOrder.append(contentsOf: firstNew..<queue.count) }
        nowPlayingHook?()
        syncHook?()
        return .added
    }

    // MARK: - Shuffle order

    /// Fisher-Yates shuffle of all queue indices except `current`, then prepend `current`
    /// so the currently-playing track is always first in the order.
    func buildShuffleOrder(keeping current: Int, total: Int) -> [Int] {
        var rest = (0..<total).filter { $0 != current }
        for i in stride(from: rest.count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0...i)
            rest.swapAt(i, j)
        }
        return [current] + rest
    }

    // MARK: - Queue editing (play-order based)

    /// Queue indices in the order they play: `shuffleOrder` under shuffle, else 0..<count.
    var playOrder: [Int] { isShuffle ? shuffleOrder : Array(queue.indices) }

    /// Index into `playOrder` of the current track.
    var playPosition: Int { isShuffle ? shufflePosition : currentIndex }

    /// Drop the given queue indices, keeping the current track, the cursor and the
    /// shuffle order pointing at the same entries.
    private func removeQueueIndices(_ doomed: Set<Int>) {
        var remap: [Int: Int] = [:]
        var next = 0
        for i in queue.indices where !doomed.contains(i) {
            remap[i] = next
            next += 1
        }
        let oldOrder = shuffleOrder
        let oldPos = shufflePosition
        let oldCurrent = currentIndex
        let oldQueue = queue
        queue = oldQueue.indices.filter { !doomed.contains($0) }.map { oldQueue[$0] }
        currentIndex = remap[oldCurrent] ?? 0
        if isShuffle {
            let clampedPos = min(oldPos, oldOrder.count)
            shuffleOrder = oldOrder.compactMap { remap[$0] }
            shufflePosition = clampedPos - oldOrder[..<clampedPos].filter { doomed.contains($0) }.count
        }
    }

    /// Move tracks within the play order. Under shuffle only `shuffleOrder` changes (the
    /// queue array keeps its order); otherwise the queue array itself is reordered.
    /// Index-based, so duplicate track ids are safe. No reshuffle.
    func moveInQueue(fromPlayPositions source: IndexSet, toPlayPosition destination: Int) {
        guard !queue.isEmpty else { return }
        if isShuffle {
            shuffleOrder.move(fromOffsets: source, toOffset: destination)
            shufflePosition = shuffleOrder.firstIndex(of: currentIndex) ?? shufflePosition
        } else {
            var order = Array(queue.indices)
            order.move(fromOffsets: source, toOffset: destination)
            let old = queue
            queue = order.map { old[$0] }
            currentIndex = order.firstIndex(of: currentIndex) ?? currentIndex
        }
        syncHook?()
    }

    /// Remove every track that plays after the current one. No-op when none are left.
    func clearUpcoming() {
        let upcoming = playOrder.dropFirst(playPosition + 1)
        guard !upcoming.isEmpty else { return }
        removeQueueIndices(Set(upcoming))
        syncHook?()
    }
}
