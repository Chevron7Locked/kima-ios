import Foundation

// Mood Mixer API methods. Paths are relative; KimaServer.api(_:) adds /api.
//   GET  /api/mixes/mood/buckets/presets              → bare [MoodBucketPreset] array
//   GET  /api/mixes/mood/buckets/:mood                → MoodBucketMix (spread, no envelope)
//   POST /api/mixes/mood/buckets/:mood/save {trackIds} → { success, mix }

/// The ids that were actually played, so the saved mix is the one the user heard. Without
/// them the server draws a fresh selection that skips the tracks it just served. The server
/// takes at most 15.
private struct MoodSaveBody: Encodable, Sendable {
    let trackIds: [String]
}

extension KimaAPIClient {

    // MARK: - Mood Mixer

    /// Track count per mood, plus how many tracks still await analysis.
    func getMoodBucketPresets() async throws -> [MoodBucketPreset] {
        try await get("/mixes/mood/buckets/presets", authed: true)
    }

    /// A fresh mix for one mood, with tracks for immediate playback.
    func getMoodBucketMix(mood: MoodType) async throws -> MoodBucketMix {
        try await get("/mixes/mood/buckets/\(mood.rawValue)", authed: true)
    }

    /// Saves the played mix as the user's mood mix. It then shows on Home as "your <mood> mix".
    func saveMoodBucketMix(mood: MoodType, trackIds: [String]) async throws {
        try await postJSONChecked(
            "/mixes/mood/buckets/\(mood.rawValue)/save",
            body: MoodSaveBody(trackIds: trackIds),
            authed: true
        )
    }
}
