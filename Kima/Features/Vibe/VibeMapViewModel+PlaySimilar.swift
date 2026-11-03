import Foundation

// MARK: - VibePanel

/// The panel open over the map, if any.
enum VibePanel: Equatable {
    case songPath
    case blend

    /// The panel's name, as its header shows it.
    var title: String {
        switch self {
        case .songPath: return "song path"
        case .blend: return "blend"
        }
    }
}

// MARK: - VibeMapViewModel + play similar

extension VibeMapViewModel {

    /// Plays `trackId` followed by its 50 nearest matches, after asking before it replaces a vibe queue.
    /// Reports a failure through `report`.
    func startPlaySimilar(trackId: String, client: KimaAPIClient, player: PlaybackController) async {
        guard !isPlayLoading else { return }
        isPlayLoading = true
        defer { isPlayLoading = false }
        modeError = nil
        do {
            async let similar = client.getVibeSimilarTracksWithSimilarity(trackId: trackId, limit: 50)
            async let seed = client.getTrack(id: trackId)
            let (similarResult, seedTrack) = try await (similar, seed)
            guard await player.confirmVibeReplace(with: .playSimilar) else { return }
            // The match badge: the seed is a perfect 1.0, each similar track carries its own score.
            var similarities = similarResult.similarities
            similarities[trackId] = 1.0
            player.playVibeQueue([seedTrack] + similarResult.tracks, origin: .playSimilar, similarities: similarities)
            operationSourceId = trackId
        } catch {
            guard !Task.isCancelled else { return }
            report(VibeErrorCopy.similar(error))
        }
    }
}
