import Foundation

// MARK: - Station refill
// A station fetches another batch when its last queued song starts (resuming at the first new song if the queue ran
// out), adds only songs it has not queued, and ends when a fetch brings nothing new. A `serverOrdered` station's
// batches are taken whole and it ends only when a fetch brings nothing. Any new queue ends the session.

/// One playing station: how to fetch its next batch and what it has queued so far.
@MainActor
final class StationSession {
    let fetchBatch: () async throws -> [Track]
    let serverOrdered: Bool
    /// Plays in the order its batches come in: shuffle is off and unavailable while it plays.
    let inOrder: Bool
    /// The listener's shuffle setting from before an in-order station turned it off, given back when it ends.
    let listenerShuffle: Bool?
    private(set) var seen: Set<String>
    private(set) var exhausted = false
    private(set) var loading = false
    /// The queue ran out while waiting for this station: the next batch that lands starts playing.
    var resumeWhenFilled = false
    /// The queue position a refill was last tried from, so one song start triggers one fetch. A refill that adds
    /// songs clears it: the queue only ends there again if the listener removes them, and then it needs more.
    private var triggeredFor: String?

    init(queued: [Track], serverOrdered: Bool, inOrder: Bool = false, listenerShuffle: Bool? = nil,
         fetchBatch: @escaping () async throws -> [Track]) {
        self.fetchBatch = fetchBatch
        self.serverOrdered = serverOrdered
        self.inOrder = inOrder
        self.listenerShuffle = listenerShuffle
        self.seen = Set(queued.map(\.id))
    }

    /// The new songs to append: none when the station is done, busy, or already tried from this position. Every
    /// id in `queuedNow` (read once the batch is in) counts as seen, so songs the listener added are not added
    /// again. A failed fetch lets the next call from the same position try again.
    func refill(triggerKey: String, queuedNow: () -> [Track]) async -> [Track] {
        if exhausted || loading || triggeredFor == triggerKey { return [] }
        triggeredFor = triggerKey
        loading = true
        defer { loading = false }
        let fetched = try? await fetchBatch()
        for track in queuedNow() { seen.insert(track.id) }
        guard let batch = fetched else {
            triggeredFor = nil
            return []
        }
        var fresh: [Track] = []
        for track in batch where serverOrdered || !seen.contains(track.id) {
            seen.insert(track.id)
            fresh.append(track)
        }
        if fresh.isEmpty { exhausted = true } else { triggeredFor = nil }
        return fresh
    }
}

extension PlaybackController {

    /// Plays a station's first batch and keeps it going. An in-order station (`inOrder`, by default a server-ordered
    /// one) plays in the order its batches come in, with shuffle off and unavailable while it plays; the listener's
    /// shuffle setting comes back when it ends. Other stations keep the listener's shuffle setting.
    func playStation(_ tracks: [Track], serverOrdered: Bool, inOrder: Bool? = nil,
                     fetchBatch: @escaping () async throws -> [Track]) {
        guard !tracks.isEmpty else { return }
        let ordered = inOrder ?? serverOrdered
        endStation()   // a station already playing gives the listener's setting back first
        let listenerShuffle = isShuffle
        play(tracks: tracks, startAt: 0, shuffle: ordered ? false : nil)
        stationSession = StationSession(queued: tracks, serverOrdered: serverOrdered, inOrder: ordered,
                                        listenerShuffle: ordered ? listenerShuffle : nil, fetchBatch: fetchBatch)
        refillStationIfAtTail()
    }

    /// Ends the station, if one is playing. One that played in order gives the listener's shuffle setting back.
    func endStation() {
        guard let session = stationSession else { return }
        stationSession = nil
        guard let shuffle = session.listenerShuffle, shuffle != isShuffle else { return }
        isShuffle = shuffle
        shuffleOrder = shuffle && !queue.isEmpty ? buildShuffleOrder(keeping: currentIndex, total: queue.count) : []
        shufflePosition = 0
    }

    /// True when the song now playing is the last one the queue will play.
    var isAtQueueTail: Bool {
        if isShuffle { return shufflePosition >= shuffleOrder.count - 1 }
        return currentIndex >= queue.count - 1
    }

    /// Called when a song starts: on the last queued song, fetch the station's next batch.
    func refillStationIfAtTail() {
        guard stationSession != nil, case .track = playbackType, !queue.isEmpty, isAtQueueTail else { return }
        refillStation(resumeIfEnded: false)
    }

    /// Fetches the next batch and appends it. With `resumeIfEnded` the queue already ran out, so the batch that
    /// lands — this one, or one already loading — starts at its first new song, unless the listener has used the
    /// transport since (`cancelStationResume`). A refill that brings nothing cancels the resume, so a later refill
    /// never starts playing on its own.
    func refillStation(resumeIfEnded: Bool) {
        guard let session = stationSession, queue.indices.contains(currentIndex) else { return }
        if resumeIfEnded { session.resumeWhenFilled = true }
        let key = "\(currentIndex):\(queue[currentIndex].id)"
        Task { @MainActor [weak self] in
            let fresh = await session.refill(triggerKey: key) { [weak self] in self?.queue ?? [] }
            // Nothing new and no other refill on its way (that one resumes, or cancels, when it lands).
            if fresh.isEmpty, !session.loading {
                session.resumeWhenFilled = false
                // A station with nothing more ends here, giving the listener's shuffle setting back.
                if session.exhausted, let self, self.stationSession === session { self.endStation() }
            }
            guard let self, self.stationSession === session, !fresh.isEmpty, case .track = self.playbackType else { return }
            // Still resting on the last song: nothing else started while the batch loaded.
            let wasAtTail = self.isAtQueueTail
            let firstNew = self.queue.count
            let firstNewPosition = self.shuffleOrder.count
            self.queue.append(contentsOf: fresh)
            if self.isShuffle {
                // In shuffle mode the new songs join the play order shuffled among themselves.
                self.shuffleOrder.append(contentsOf: (firstNew..<self.queue.count).shuffled())
            }
            if session.resumeWhenFilled, wasAtTail, !self.isPlaying {
                session.resumeWhenFilled = false
                if self.isShuffle {
                    self.shufflePosition = firstNewPosition
                    self.currentIndex = self.shuffleOrder[firstNewPosition]
                } else {
                    self.currentIndex = firstNew
                }
                self.loadCurrentTrack(autoplay: true)
            }
            self.nowPlayingHook?()
            self.syncHook?()
        }
    }

    /// The listener used the transport (play, pause, skip, seek, a queue jump): a station refill still on its way
    /// only appends its songs and does not start playing.
    func cancelStationResume() {
        stationSession?.resumeWhenFilled = false
    }
}
