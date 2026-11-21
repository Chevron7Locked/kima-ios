import AVFoundation
import Foundation

// MARK: - Seeking, and exact seeks in FLAC
//
// Apple's player seeks a FLAC by estimating a byte position and decodes from wherever that lands
// while reporting the time asked for: seconds off, so lyrics, scrubber and lock screen ran ahead of
// or behind the sound after every skip. A FLAC that starts at a frame boundary plays from that
// frame exactly, so a FLAC is never seeked: the engine swaps in a stream that starts at the frame
// holding the target (`FLACTailLoader`) and counts the track's time from that frame's sample.
// Other formats seek the item as before.

/// The current load's FLAC seek state. Reset by every load.
struct FLACSeekState {
    /// What the current stream is, as far as starting it mid-track goes.
    enum Kind {
        /// Not asked yet, or the last ask failed.
        case unknown
        /// Another format, or a FLAC this can't start mid-track: the item seeks itself.
        case other
        case flac(FLACStream)
    }

    /// The stream URL of the current load; nil when idle.
    var source: URL?
    var kind: Kind = .unknown
    /// The header read finding out `kind`, shared by seeks that ask while it's out.
    var probe: Task<FLACStream?, Error>?
    /// What the current item is serving, when it starts mid-track. Retained: assets hold it weakly.
    var loader: FLACTailLoader?
    /// Seconds into the track at the current item's time zero.
    var startOffset: Double = 0
    /// The seek in flight, if any: while one is, the 1 Hz clock holds the shown target.
    var seek: Task<Void, Never>?
    /// A skip swapped the item while playing: it goes on showing playing (`isPlaying`) through the
    /// swap's moment of no sound, as a seek's buffering does, until the new item plays. The
    /// user's pause or a call ends it (`endSwapHold`).
    var holdsPlaying = false
    var seekID = 0
}

extension PlaybackEngine {

    /// Seek to `seconds` into the track. A FLAC restarts at the frame there (below); anything
    /// else takes a zero-tolerance item seek.
    func seek(to seconds: Double) {
        let target = max(0, seconds)
        currentTime = target  // optimistic: the 1 Hz observer only reports while playing
        // Nothing to move: a failed track is rebuilt at `currentTime` (the controller's recovery
        // point), so an older resume position must not outrank the skip.
        if status == .error || status == .idle { pendingSeek = nil; return }
        // A skip while the whole track is still loading becomes the position it starts at: ready
        // lands it before playing, so the start never plays first. A restarted stream starts
        // mid-track, so a skip there restarts again instead.
        if status == .loading, lastDeliveredStatus != .readyToPlay, !isRestartedStream {
            pendingSeek = target.asStartPosition
            return
        }
        land(at: target)
    }

    /// Moves the current item to `seconds` into the track: the one path for the user's skips and the
    /// resume seek applied at ready. A seek landing while a resume is unfinished finishes it.
    func land(at seconds: Double) {
        let gen = generation
        seekTrack(to: seconds) { [weak self] itemTime in
            guard let self else { return }
            // The item starts at `startOffset`: a skip before that can only land at the start.
            let clamped = max(0, itemTime), landed = self.flacSeek.startOffset + clamped
            self.currentTime = landed
            let t = CMTime(seconds: clamped, preferredTimescale: 1000)
            self.player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                Task { @MainActor [weak self] in
                    guard let self, self.pendingSeek != nil else { return }
                    self.finishResumeSeek(finished: finished, target: landed, generation: gen)
                }
            }
        }
    }

    /// Called by every load and teardown: a new stream knows nothing yet, unless `kind` says.
    func resetFLACSeek(source: URL?, kind: FLACSeekState.Kind? = nil) {
        flacSeek.seek?.cancel()
        flacSeek.probe?.cancel()
        let isHTTP = source?.scheme == "http" || source?.scheme == "https"
        flacSeek = FLACSeekState(source: source, kind: kind ?? (isHTTP ? .unknown : .other))
    }

    var isFLACSeekInFlight: Bool { flacSeek.seek != nil }

    /// The current item is a stream restarted mid-track. Its failing or stalling isn't the track's:
    /// it falls back to the whole track (`fallBackToWholeTrack`), not to the recovery ladder.
    var isRestartedStream: Bool { flacSeek.loader != nil }

    /// True when a seek must take the FLAC path (or find out whether it must).
    private var mayBeFLAC: Bool {
        guard flacSeek.source != nil else { return false }
        if case .other = flacSeek.kind { return false }
        return true
    }

    /// Seek to `seconds` into the track. `itemSeek` is the plain path (the item's own seek, in
    /// track time), taken for a stream that isn't FLAC, or when the start can't be found.
    private func seekTrack(to seconds: Double, itemSeek: @escaping @MainActor (Double) -> Void) {
        flacSeek.seek?.cancel()
        flacSeek.seek = nil
        // Time zero of an untrimmed item is exact in any format.
        guard mayBeFLAC, !(seconds == 0 && flacSeek.startOffset == 0) else {
            itemSeek(seconds - flacSeek.startOffset)
            return
        }
        flacSeek.seekID += 1
        let id = flacSeek.seekID, gen = generation
        flacSeek.seek = Task { [weak self] in
            guard let self else { return }
            let started = await self.startFLAC(at: seconds)
            guard !Task.isCancelled, self.flacSeek.seekID == id else { return }   // a newer seek or load owns it
            self.flacSeek.seek = nil
            if !started, self.generation == gen { itemSeek(seconds - self.flacSeek.startOffset) }
        }
    }

    /// Finds the frame for `seconds` and swaps in a stream starting there. False when the stream
    /// isn't FLAC, the frame couldn't be found, or a newer load or seek took over.
    private func startFLAC(at seconds: Double) async -> Bool {
        let gen = generation
        guard let source = flacSeek.source, let stream = await flacStream(of: player.currentItem?.asset),
              !Task.isCancelled, generation == gen else { return false }
        guard let start = try? await stream.start(at: seconds, from: .http(source, session: streamSession)),
              !Task.isCancelled, generation == gen else { return false }
        installTail(FLACTailLoader(source: source, stream: stream, start: start, session: streamSession), sampleRate: stream.layout.sampleRate)
        return true
    }

    /// The stream's FLAC layout, read once per load; nil when it isn't one this can start mid-track.
    /// The item's own format answers first, so only a FLAC's header is read from the server.
    /// A read that failed (a blip) is no answer: the next seek reads again.
    private func flacStream(of asset: AVAsset?) async -> FLACStream? {
        switch flacSeek.kind {
        case .flac(let stream): return stream
        case .other: return nil
        case .unknown: break
        }
        guard let source = flacSeek.source else { return nil }
        if let asset, await !Self.formatMayBeFLAC(asset) {
            if flacSeek.source == source { flacSeek.kind = .other }
            return nil
        }
        let probe = flacSeek.probe ?? Task { try await FLACStream.read(from: .http(source, session: streamSession)) }
        flacSeek.probe = probe
        do {
            let stream = try await probe.value
            if flacSeek.source == source { flacSeek.kind = stream.map { .flac($0) } ?? .other }
            return stream
        } catch {
            if flacSeek.source == source { flacSeek.probe = nil }
            return nil
        }
    }

    /// False when the asset's audio is known to be another format; true when it's FLAC or unknown.
    private static func formatMayBeFLAC(_ asset: AVAsset) async -> Bool {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let formats = try? await track.load(.formatDescriptions), !formats.isEmpty else { return true }
        return formats.contains { $0.mediaSubType.rawValue == kAudioFormatFLAC }
    }

    /// Replaces the item with one that starts at `loader.start`, keeping the user's play/pause.
    /// Not a load: play-intent claims, the recovery budget and the queue are untouched.
    private func installTail(_ loader: FLACTailLoader, sampleRate: Int) {
        swapItem(to: AVPlayerItem(asset: loader.makeAsset())) {
            pendingSeek = nil   // the new item starts where the seek wanted: nothing left to apply
            flacSeek.loader = loader
            flacSeek.startOffset = Double(loader.start.sample) / Double(sampleRate)
            currentTime = flacSeek.startOffset
            // A playing player keeps its rate (a long-form speed, or one set while this loads) across
            // the swap and starts the new item when it's ready: ready only plays a stopped player.
            if !wantsPlayback { player.pause() }
        }
    }

    /// The stream restarted mid-track failed or stalled: put the whole track back at the same spot
    /// with the item's own seek, and stop restarting for this load. Handing it to the recovery ladder
    /// would loop: the rebuilt track's ready resets the budget, its resume restarts, and that fails
    /// again. A real drop fails the whole track too, and goes to the ladder from there.
    func fallBackToWholeTrack() {
        guard let source = flacSeek.source else { return }
        let position = currentTime
        swapItem(to: AVPlayerItem(url: source)) {
            resetFLACSeek(source: source, kind: .other)
            pendingSeek = position.asStartPosition   // ready lands it, then plays if it was running
            // An engine the user wants playing waits for the new item, even one the failing stream
            // left paused (not .paused: the pause below is the swap, not the user's); one the user
            // or the OS stopped stays as it is.
            if wantsPlayback, !isInterrupted, status != .blocked { status = .loading }
            player.pause()
        }
    }

    /// Swaps in `item` within the current load. `prepare` sets the state the new item starts from.
    private func swapItem(to item: AVPlayerItem, prepare: () -> Void) {
        let myGen = retireItem()
        // Shown playing and really running (or held through a skip just before): not stopped by
        // the OS ahead of its KVO.
        let wasRunning = isPlaying && wantsPlayback && !isInterrupted && status.isRunning
            && (player.rate != 0 || flacSeek.holdsPlaying)
        prepare()
        flacSeek.holdsPlaying = wasRunning
        player.replaceCurrentItem(with: item)
        setupItemObservers(item: item, generation: myGen)
        updateStallWatchdog()
    }

    /// The swap is over: its new item is ready and playing.
    func endSwapHoldIfPlaying() {
        if player.currentItem?.status == .readyToPlay, player.timeControlStatus == .playing {
            flacSeek.holdsPlaying = false
        }
    }

    /// The swap's playing is over before the new item plays: the user paused, or a call came in.
    func endSwapHold() {
        guard flacSeek.holdsPlaying else { return }
        flacSeek.holdsPlaying = false
        if isPlaying, player.timeControlStatus != .playing {
            isPlaying = false
            onPlaybackStateChanged?()
        }
    }

    /// Retires the current item for the next one, by a load or a swap: a new generation, the old
    /// item's observers and stall window gone, and status dedupe starting over. Returns the generation.
    func retireItem() -> Int {
        let myGen = nextGeneration()
        teardownItemObservers()
        cancelStallWatchdog()
        lastDeliveredStatus = nil
        return myGen
    }
}

extension Double {
    /// This time as a position an item starts at: the top is no position, so a load or a
    /// pre-ready skip to 0 plays from the start without a seek. Every caller passes raw times.
    var asStartPosition: Double? { self > 0 ? self : nil }
}
