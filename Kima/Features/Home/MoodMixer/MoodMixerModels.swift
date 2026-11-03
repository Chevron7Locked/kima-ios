import Foundation

// MARK: - MoodType

/// The five moods the server sorts tracks into. Raw values are the path segments of
/// /mixes/mood/buckets/:mood. The server answers 400 for energetic, focus, melancholy and acoustic.
enum MoodType: String, Codable, Sendable, CaseIterable, Identifiable {
    case happy, party, chill, sad, aggressive

    var id: String { rawValue }
}

// MARK: - MoodBucketPreset

/// GET /mixes/mood/buckets/presets → [MoodBucketPreset]
/// Server sends { id, name, color, icon, trackCount, pendingTracks }; color and icon are not
/// used on iOS (tiles take their colours from VibeMoodPalette), so they are not decoded.
/// `id` is a String so a mood this app doesn't know can't fail the whole array's decode.
struct MoodBucketPreset: Decodable, Sendable {
    let id: String
    let name: String
    let trackCount: Int
    /// Library tracks still waiting for mood analysis (the same number on every preset).
    let pendingTracks: Int?
}

// MARK: - MoodBucketMix

/// GET /mixes/mood/buckets/:mood → { id, mood, name, description, trackIds, coverUrls,
/// trackCount, color, tracks } (spread, no envelope). Only `tracks` is played. Tracks decode
/// via `MixTrack` (HomeModels.swift) because the album cover arrives as `coverUrl`.
struct MoodBucketMix: Decodable, Sendable {
    let id: String
    let name: String
    let tracks: [MixTrack]?
}
