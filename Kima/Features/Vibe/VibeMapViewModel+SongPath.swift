import Foundation

/// The two ends of a song path. Pure, so the rules can be tested.
struct VibeSongPathForm: Equatable {
    enum Slot { case start, end }

    var start: VibeTrackPick?
    var end: VibeTrackPick?

    /// The end still to fill, start first; nil once both are set.
    var nextSlot: Slot? { start == nil ? .start : (end == nil ? .end : nil) }
    var sameTrack: Bool { start != nil && start?.id == end?.id }
    var canGenerate: Bool { start != nil && end != nil && !sameTrack }

    /// Fills the next empty end. Once both are set it changes nothing: an end then changes only by its
    /// ×, "set as start" / "set as end" or the swap. True when an end was filled.
    @discardableResult
    mutating func fill(_ pick: VibeTrackPick) -> Bool {
        switch nextSlot {
        case .start: start = pick
        case .end: end = pick
        case nil: return false
        }
        return true
    }

    mutating func clear(_ slot: Slot) {
        set(slot, to: nil)
    }

    mutating func set(_ slot: Slot, to pick: VibeTrackPick?) {
        switch slot {
        case .start: start = pick
        case .end: end = pick
        }
    }

    /// The start becomes the end and the end the start; an empty end moves too.
    mutating func swap() {
        (start, end) = (end, start)
    }
}

extension VibeMapViewModel {

    /// A track on the loaded map as a pick; nil when it is not on the map.
    func pick(forTrackId id: String) -> VibeTrackPick? {
        trackFor(id: id).map { VibeTrackPick(id: $0.id, title: $0.title, artist: $0.artist) }
    }

    /// "song path" from a star: opens the song path with that star as the start and keeps it selected.
    /// An end picked earlier stays unless it is the same star; otherwise the end is a star tapped on the
    /// map or a search pick.
    func beginSongPath(from trackId: String) {
        panel = .songPath
        songPath.start = pick(forTrackId: trackId)
        if songPath.sameTrack { songPath.end = nil }
        modeError = nil
    }

    /// A star tapped while the song path waits for an end fills it.
    func pickPathTrack(_ id: String) {
        guard let p = pick(forTrackId: id) else { return }
        songPath.fill(p)
        modeError = nil
    }

    /// "set as start" / "set as end": the selected star replaces that end of the song path.
    func setSelected(as slot: VibeSongPathForm.Slot) {
        guard let id = selectedTrackId, let p = pick(forTrackId: id) else { return }
        songPath.set(slot, to: p)
        modeError = nil
    }

    /// The selected star while both ends are set, when it is neither end: the panel offers "set as
    /// start" and "set as end".
    var pathCandidate: VibeTrackPick? {
        guard panel == .songPath, songPath.nextSlot == nil, let id = selectedTrackId,
              id != songPath.start?.id, id != songPath.end?.id else { return nil }
        return pick(forTrackId: id)
    }

    /// The song path's ends, ringed on the map while the panel is open.
    var pathStartMark: String? { panel == .songPath ? songPath.start?.id : nil }
    var pathEndMark: String? { panel == .songPath ? songPath.end?.id : nil }

    /// Plays `[start] + path + [end]` (12 steps, smooth). True when the queue was replaced; the two ends
    /// are then used up and the next song path starts empty.
    @discardableResult
    func finishSongPath(from start: String, to end: String,
                        client: KimaAPIClient, player: PlaybackController) async -> Bool {
        do {
            let resp = try await client.vibePath(
                startTrackId: start, endTrackId: end, length: 12, mode: "smooth")
            let queue: [Track] = [resp.startTrack.asTrack()]
                + resp.path.map { $0.asTrack() }
                + [resp.endTrack.asTrack()]
            guard await player.confirmVibeReplace(with: .songPath) else { return false }
            player.playVibeQueue(queue, origin: .songPath)
            operationSourceId = start
            songPath = VibeSongPathForm()
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            report(VibeErrorCopy.path(error))
            return false
        }
    }
}
