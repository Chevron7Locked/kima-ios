import Foundation
import simd

/// Where a mood's name floats on the map: the densest pocket of that mood's tracks.
struct VibeMoodAnchor {
    let mood: String
    /// Lowercase display name.
    let label: String
    /// Unit-cube map coordinates of the pocket.
    let x: Double, y: Double, z: Double
    /// Tracks of this mood in the whole library.
    let count: Int
    var world: SIMD3<Float> { VibeField.toWorld(x: x, y: y, z: z) }
}

enum VibeMoodAnchors {
    static let grid = 6
    static let labels: [String: String] = [
        "moodHappy": "upbeat", "moodSad": "melancholic", "moodRelaxed": "calm",
        "moodAggressive": "intense", "moodParty": "energetic",
    ]

    /// JavaScript `Math.round`: halves go up.
    static func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

    static func minCount(trackCount n: Int) -> Int { max(3, jsRound(Double(n) * 0.02)) }

    static func compute(tracks: [VibeMapTrack], maxLabels: Int = 7) -> [VibeMoodAnchor] {
        // Reference types on purpose. As value types the per-track step copied the whole
        // mood bucket (a dictionary plus an array) out of the map and back on every track:
        // on this host that made the map's arrival pass 65-69 ms at 100k tracks, and the
        // same algorithm over reference cells runs 4.9-5.1 ms with identical output.
        final class Cell { var n = 0; var x = 0.0, y = 0.0, z = 0.0 }
        final class Bucket { var total = 0; var keys = [Int](); var cells = [Int: Cell]() }
        var moods = [String](), per = [String: Bucket]()
        // One closure built once, not once per track.
        let axis: (Double) -> Int = { v in min(grid - 1, max(0, Int((v * Double(grid)).rounded(.down)))) }
        for t in tracks {
            let m = t.dominantMood
            guard labels[m] != nil else { continue }
            let bucket: Bucket
            if let seen = per[m] { bucket = seen } else { bucket = Bucket(); per[m] = bucket; moods.append(m) }
            let key = (axis(t.z) * grid + axis(t.y)) * grid + axis(t.x)
            bucket.total += 1
            let cell: Cell
            if let filled = bucket.cells[key] { cell = filled } else { cell = Cell(); bucket.keys.append(key); bucket.cells[key] = cell }
            cell.n += 1
            cell.x += t.x; cell.y += t.y; cell.z += t.z
        }
        let floor = minCount(trackCount: tracks.count)
        var out = [VibeMoodAnchor]()
        for m in moods {
            let p = per[m]!
            guard p.total >= floor else { continue }
            var best: Cell?
            for k in p.keys { let c = p.cells[k]!; if best == nil || c.n > best!.n { best = c } }
            guard let b = best else { continue }
            out.append(VibeMoodAnchor(mood: m, label: labels[m]!, x: b.x / Double(b.n), y: b.y / Double(b.n),
                                      z: b.z / Double(b.n), count: p.total))
        }
        // Stable: the biggest mood first, equal moods in the order first seen.
        let ranked = out.enumerated().sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
        return Array(ranked.map(\.element).prefix(maxLabels))
    }
}
