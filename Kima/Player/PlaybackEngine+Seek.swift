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
    var seekID = 0
}

extension PlaybackEngine {

    /// Seek to `seconds` into the track. A FLAC restarts at the frame there (below); anything
    /// else takes a zero-tolerance item seek.
    func seek(to seconds: Double) {
        let target = max(0, seconds)
        currentTime = target  // optimistic: the 1 Hz observer only reports while playing
        // A skip while the whole track is still loading becomes the position it starts at: ready
        // lands it before playing, so the start never plays first. The top is no position (as in
        // `load`). A restarted stream starts mid-track, so a skip there restarts again instead.
        if status == .loading, lastDeliveredStatus != .readyToPlay, !isRestartedStream {
            pendingSeek = target > 0 ? target : nil
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

    /// Called by every load and teardown: a new stream knows nothing yet.
    func resetFLACSeek(source: URL?) {
        flacSeek.seek?.cancel()
        flacSeek.probe?.cancel()
        let isHTTP = source?.scheme == "http" || source?.scheme == "https"
        flacSeek = FLACSeekState(source: source, kind: isHTTP ? .unknown : .other)
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
            flacSeek.seek?.cancel()
            flacSeek = FLACSeekState(source: source, kind: .other)
            pendingSeek = position > 0 ? position : nil   // ready lands it, then plays per wantsPlayback
            status = .loading   // not .paused: the pause below is the swap, not the user's
            player.pause()
        }
    }

    /// Swaps in `item` within the current load: a new generation retires the old item's observers
    /// and stall window. `prepare` sets the state the new item starts from.
    private func swapItem(to item: AVPlayerItem, prepare: () -> Void) {
        let myGen = nextGeneration()
        teardownItemObservers()
        cancelStallWatchdog()
        lastDeliveredStatus = nil
        prepare()
        player.replaceCurrentItem(with: item)
        setupItemObservers(item: item, generation: myGen)
        updateStallWatchdog()
    }
}
