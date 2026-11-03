#if DEBUG
import Foundation

/// `-kima-vibe-synthetic`: a made-up map of 9,000 tracks in two bodies, so the map can be drawn and
/// screenshotted with no server and no sign-in. Same shape as `KimaTests/VibeSyntheticMap`.
enum VibeDebugSyntheticMap {
    static func responseIfRequested() -> VibeMapResponse? {
        guard CommandLine.arguments.contains("-kima-vibe-synthetic") else { return nil }
        return response(count: 9000)
    }

    /// Roughly bell-shaped value in about -0.3...0.3 from three fixed pseudo-random draws.
    private static func bell(_ i: Int, _ salt: Int) -> Double {
        (VibeField.hash01(i, salt) + VibeField.hash01(i, salt + 100) + VibeField.hash01(i, salt + 200) - 1.5) * 0.2
    }

    static func response(count n: Int) -> VibeMapResponse {
        let moods = VibeField.moodKeys + ["neutral"]
        let tracks: [VibeMapTrack] = (0..<n).map { i in
            let left = i < n / 2
            let dx = bell(i, 21) * 1.2
            let x = (left ? 0.27 : 0.73) + dx
            // Colour follows position inside each body, so the haze shows a gradient.
            let colour = min(1, max(0, (left ? 0.25 : 0.75) + dx * 1.5 + bell(i, 24) * 0.5))
            let mood = moods[Int(VibeField.hash01(i, 25) * Double(moods.count)) % moods.count]
            return VibeMapTrack(
                id: "synthetic-\(i)",
                x: x, y: 0.5 + bell(i, 22) * 0.9, z: 0.5 + bell(i, 23) * 0.8,
                title: VibeDebugFlags.longTitle ? "synthetic \(i) with a title far too long to fit on one line" : "synthetic \(i)", artist: "synthetic", artistId: "ar", albumId: "al", coverUrl: nil,
                dominantMood: mood, moodScore: 0.5, moods: [:],
                energy: VibeField.hash01(i, 26), valence: nil, colour: colour)
        }
        return VibeMapResponse(tracks: tracks, trackCount: n, computedAt: "2026-10-07T00:00:00Z", moodSignature: "synthetic")
    }
}
#endif
