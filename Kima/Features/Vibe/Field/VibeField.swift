import Foundation
import simd

/// Per-star data for the 3-d map. Stars keep the order
/// the server sent them in; every random-looking value below is a fixed function of that index,
/// so a star twinkles the same way on every visit.
struct VibeField {
    /// Half-width of the map in world units: unit-cube coordinates span +-60.
    static let fieldRadius: Float = 60
    static let moodKeys = ["moodHappy", "moodSad", "moodRelaxed", "moodAggressive", "moodParty"]
    static let revealFade: Float = 0.3

    /// Fixed pseudo-random number in 0..<1 from a star index and a salt (web `hash01`), bit for bit.
    static func hash01(_ i: Int, _ salt: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: UInt64(truncatingIfNeeded: i) &* 2654435761)
            ^ UInt32(truncatingIfNeeded: salt &* 40503)
        h = (h ^ (h >> 15)) &* 2246822519
        h = (h ^ (h >> 13)) &* 3266489917
        return Double(h ^ (h >> 16)) / 4294967296
    }

    /// Map coordinates (unit cube) to world space: x stays x, map z (height) becomes world y,
    /// map y becomes world depth.
    static func toWorld(x: Double, y: Double, z: Double) -> SIMD3<Float> {
        let s = Double(fieldRadius) * 2
        return SIMD3(Float((x - 0.5) * s), Float((z - 0.5) * s), Float((y - 0.5) * s))
    }

    static func toWorld(_ t: VibeMapTrack) -> SIMD3<Float> { toWorld(x: t.x, y: t.y, z: t.z) }

    /// FNV-1a, 32 bit, over a track id's UTF-8 bytes. Decorative values come from the id so a star
    /// keeps its look when the library grows or is reordered.
    static func fnv1a32(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return h
    }

    let count: Int
    let trackIds: [String]
    let positions: [SIMD3<Float>]
    /// Linear-light starlight colour, scaled by brightness.
    let colours: [SIMD3<Float>]
    let sizes: [Float]
    let phases: [Float]
    let twinkleAmps: [Float]
    /// Seconds after the map opens at which each star starts to light up.
    let reveals: [Float]
    let indexById: [String: Int]
    let centre: SIMD3<Float>
    /// Distance from the centre that holds 90% of the stars.
    let radius: Float
    /// Seconds until the last star has finished its fade-in.
    let revealDuration: Float
    /// Dominant mood index per star (`moodKeys` index, -1 for an unknown mood).
    let moods: [Float]
    /// The reference star size the queue chart's step is scaled from (web `baseSize`).
    let baseSize: Float

    init(tracks: [VibeMapTrack]) {
        let n = tracks.count
        var positions = [SIMD3<Float>](), colours = [SIMD3<Float>](), sizes = [Float](), phases = [Float]()
        var twinkle = [Float](), ids = [String]()
        var indexById = [String: Int]()
        let white = VibeMapStyle.starlight
        var sum = SIMD3<Double>(repeating: 0)
        for (i, t) in tracks.enumerated() {
            ids.append(t.id)
            indexById[t.id] = i
            let w = Self.toWorld(t)
            positions.append(w)
            sum += SIMD3<Double>(w)
            let seed = Int(Self.fnv1a32(t.id))
            let notable = Self.hash01(seed, 6) < VibeMapStyle.notableShare
            let b: Float = notable
                ? Float(0.70 + 0.30 * Self.hash01(seed, 7))
                : VibeMapStyle.faintLow + (VibeMapStyle.faintHigh - VibeMapStyle.faintLow) * Float(Self.hash01(seed, 7))
            let size = notable ? 1.50 + 0.80 * Self.hash01(seed, 8) : 0.70 + 0.40 * Self.hash01(seed, 8)
            colours.append(white * (VibeMapStyle.starColourScale * b))
            sizes.append(Float(size))
            phases.append(Float(Self.hash01(seed, 1) * 2 * Double.pi))
            twinkle.append(Float(0.14 + 0.20 * Self.hash01(seed, 2)))
        }
        let mean = n > 0 ? sum / Double(n) : SIMD3<Double>(repeating: 0)
        var dists = [Float]()
        dists.reserveCapacity(n)
        for p in positions {
            let d = SIMD3<Double>(p) - mean
            dists.append(Float((d * d).sum().squareRoot()))
        }
        let sorted = dists.sorted()
        let radius = max(8, n > 0 ? sorted[Int(Double(n - 1) * 0.9)] : Self.fieldRadius)
        let maxDist = n > 0 ? (sorted[n - 1] == 0 ? 1 : sorted[n - 1]) : 1

        var reveals = [Float](), duration: Float = 0
        for i in 0..<n {
            let angle = atan2(Double(positions[i].z) - mean.z, Double(positions[i].x) - mean.x)
            let sector = min(7, Int(((angle + Double.pi) / (2 * Double.pi) * 8).rounded(.down)))
            let delay = Double(sector) * 0.15 + Double(dists[i] / maxDist) * 0.22 + (Self.hash01(i, 5) - 0.5) * 0.16
            let r = Float(max(0, delay))
            reveals.append(r)
            duration = max(duration, r + Self.revealFade)
        }
        self.count = n
        self.trackIds = ids
        self.positions = positions
        self.colours = colours
        self.sizes = sizes
        self.phases = phases
        self.twinkleAmps = twinkle
        self.reveals = reveals
        self.indexById = indexById
        self.centre = SIMD3<Float>(mean)
        self.radius = radius
        self.revealDuration = duration
        self.moods = tracks.map { Float(Self.moodKeys.firstIndex(of: VibeMoodPalette.paletteKey(forAxis: $0.dominantMood)) ?? -1) }
        self.baseSize = Float(min(2.4, max(0.7, 5.0 / pow(Double(max(n, 1)), 0.12))))
    }
}
