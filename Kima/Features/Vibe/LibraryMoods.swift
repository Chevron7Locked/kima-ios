import Foundation

// MARK: - LibraryMoods

/// The main mood of each song, album and artist, and each mood's share of the library, read from the vibe map.
/// Only the five moods mark anything: a song with no single mood, or not analysed yet, has none, and an album or
/// artist takes the mood most of its songs share (none when that is "no single mood").
struct LibraryMoods: Sendable {

    /// One stretch of the library's mood band: a palette key ("moodRelaxed", or "neutral" for no single mood).
    struct Share: Sendable, Equatable, Identifiable {
        let key: String
        let fraction: Double
        var id: String { key }
    }

    private(set) var trackMood: [String: String] = [:]
    private(set) var albumMood: [String: String] = [:]
    private(set) var artistMood: [String: String] = [:]
    /// The five moods biggest first, then "no single mood", as fractions of the analysed songs.
    private(set) var shares: [Share] = []

    static let empty = LibraryMoods()

    private init() {}

    init(tracks: [VibeMapTrack]) {
        var albums: [String: [String: Int]] = [:]
        var artists: [String: [String: Int]] = [:]
        var counts: [String: Int] = [:]
        var analysed = 0
        for t in tracks {
            let raw = VibeMoodPalette.paletteKey(forAxis: t.dominantMood)
            if raw == "unanalyzed" { continue }
            let key = VibeMoodPalette.isMood(raw) ? raw : "neutral"
            analysed += 1
            counts[key, default: 0] += 1
            albums[t.albumId, default: [:]][key, default: 0] += 1
            artists[t.artistId, default: [:]][key, default: 0] += 1
            if key != "neutral" { trackMood[t.id] = key }
        }
        albumMood = albums.compactMapValues(Self.mainMood)
        artistMood = artists.compactMapValues(Self.mainMood)
        guard analysed > 0 else { return }
        // Biggest first; equal counts keep the legend's order (`sorted` is not stable, so the position decides).
        let order = VibeMoodPalette.moodKeys
        let present: [(position: Int, count: Int)] = order.indices.compactMap { i in
            guard let n = counts[order[i]] else { return nil }
            return (i, n)
        }
        let ranked = present.sorted { a, b in a.count != b.count ? a.count > b.count : a.position < b.position }
        let total = Double(analysed)
        shares = ranked.map { Share(key: order[$0.position], fraction: Double($0.count) / total) }
        if let n = counts["neutral"] { shares.append(Share(key: "neutral", fraction: Double(n) / total)) }
    }

    /// The key with the most songs (ties go to the legend's order, moods before "no single mood"); nil when
    /// that is "no single mood".
    private static func mainMood(_ counts: [String: Int]) -> String? {
        var best: (key: String, n: Int)?
        for key in VibeMoodPalette.moodKeys + ["neutral"] {
            if let n = counts[key], n > (best?.n ?? 0) { best = (key, n) }
        }
        return best?.key == "neutral" ? nil : best?.key
    }
}
