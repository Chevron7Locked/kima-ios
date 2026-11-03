import Foundation
import Observation

// MARK: - Loaded-map index and lookup
//
// Split out of VibeMapViewModel. Methods only, same code and same call order; the helpers that
// were `private` are internal so `apply` in the class file can call them.

extension VibeMapViewModel {

    /// Top-3 mood keys by frequency across `tracks` — the `Dictionary(grouping:)` pass is O(n)
    /// over the full track set, so it's run here (once per load) rather than in a SwiftUI body.
    static func computeTopMoods(from tracks: [VibeMapTrack]) -> [String] {
        guard !tracks.isEmpty else { return [] }
        let counts = Dictionary(grouping: tracks, by: \.dominantMood).mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
    }

    // MARK: - Selection helpers

    /// Look up a VibeMapTrack by id from the loaded phase for the card UI.
    func trackFor(id: String) -> VibeMapTrack? {
        guard case .loaded(let tracks) = phase else { return nil }
        return tracks.first { $0.id == id }
    }
}
