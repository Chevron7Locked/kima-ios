import Foundation
@testable import Kima

/// Hand-written fixture shared by the vibe-map maths tests: 400 tracks in two bodies along x.
/// The left body (i < 200) sits near x = 0.2, colour 0.06, sad/relaxed; the right near x = 0.8,
/// colour 0.92, mostly aggressive with every tenth track "neutral". Energy is nil.
enum VibeSyntheticMap {
    static func tracks(count n: Int = 400) -> [VibeMapTrack] {
        (0..<n).map { i in
            let left = i < n / 2
            let mood = left ? (i % 2 == 1 ? "moodSad" : "moodRelaxed") : (i % 10 == 0 ? "neutral" : "moodAggressive")
            return VibeMapTrack(
                id: "t\(i)",
                x: (left ? 0.2 : 0.8) + (VibeField.hash01(i, 21) - 0.5) * 0.3,
                y: 0.5 + (VibeField.hash01(i, 22) - 0.5) * 0.4,
                z: 0.5 + (VibeField.hash01(i, 23) - 0.5) * 0.4,
                title: "t\(i)", artist: "a", artistId: "ar", albumId: "al", coverUrl: nil,
                dominantMood: mood, moodScore: 0.5, moods: [:], energy: nil, valence: nil,
                colour: left ? 0.06 : 0.92)
        }
    }
}
