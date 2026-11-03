import Foundation

/// One track picked for a blend or a song path end.
struct VibeTrackPick: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
}

/// The "more like" and "less like" lists behind the blend panel. Pure.
struct VibeBlendPicks: Equatable {
    enum Column { case more, less }

    var more: [VibeTrackPick] = []
    var less: [VibeTrackPick] = []

    /// Adds to a column unless that column already has the track.
    mutating func add(_ pick: VibeTrackPick, to column: Column) {
        switch column {
        case .more: if !more.contains(where: { $0.id == pick.id }) { more.append(pick) }
        case .less: if !less.contains(where: { $0.id == pick.id }) { less.append(pick) }
        }
    }

    mutating func remove(_ id: String, from column: Column) {
        switch column {
        case .more: more.removeAll { $0.id == id }
        case .less: less.removeAll { $0.id == id }
        }
    }

    var canBlend: Bool { !more.isEmpty }
}

extension VibeMapViewModel {

    /// "more like" / "less like" from the readout, or the rail's blend with a star selected: opens the
    /// blend panel if it is closed and adds the star.
    func addToBlend(_ trackId: String, column: VibeBlendPicks.Column) {
        guard let p = pick(forTrackId: trackId) else { return }
        if panel != .blend { panel = .blend }
        blendPicks.add(p, to: column)
        blendResults = []
    }

    /// Blend the picks (`/vibe/alchemy`, 30 results). Nothing plays; the stars light up and the list shows.
    func runBlend(picks: VibeBlendPicks, client: KimaAPIClient) async {
        guard picks.canBlend else { return }
        blendRequest += 1
        let request = blendRequest
        isBlending = true
        modeError = nil
        defer { if request == blendRequest { isBlending = false } }
        do {
            let resp = try await client.vibeAlchemy(
                add: picks.more.map(\.id), subtract: picks.less.map(\.id), limit: 30)
            // A closed or reopened panel, or a newer blend, makes this answer stale.
            guard panel == .blend, request == blendRequest else { return }
            blendResults = resp.tracks
        } catch {
            guard panel == .blend, request == blendRequest else { return }
            blendResults = []
            modeError = VibeErrorCopy.alchemy(error)
        }
    }

    /// Replace the queue with the blend result and play it.
    func playBlendResult(player: PlaybackController) async {
        guard !blendResults.isEmpty else { return }
        guard await player.confirmVibeReplace(with: .blend) else { return }
        player.playVibeQueue(blendResults.map { $0.asTrack() }, origin: .blend)
        operationSourceId = nil
    }
}
