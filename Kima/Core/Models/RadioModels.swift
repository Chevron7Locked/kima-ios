import Foundation

// MARK: - API-decoded types

/// Genre + track count from GET /api/library/genres.
struct RadioGenre: Codable, Sendable, Identifiable {
    let genre: String
    let count: Int
    var id: String { genre }
}

/// Decade (year floor) + track count from GET /api/library/decades.
struct RadioDecade: Codable, Sendable, Identifiable {
    let decade: Int
    let count: Int
    var id: Int { decade }
}

/// One mood station from GET /api/library/radio/stations. `value` is passed as `type=mood&value=`.
struct MoodStationInfo: Decodable, Sendable, Equatable {
    let value: String
    let name: String
    let description: String
}

/// One batch from GET /api/library/radio. `next` is present only for stations the server orders
/// (mood, wildcard, workout): the offset to ask from next with the same seed.
struct RadioPage: Decodable, Sendable {
    let tracks: [Track]
    let next: Int?

    /// A fresh seed for one station session: 1–128 of `A-Za-z0-9_-`, as the server requires.
    static func newSeed() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

// MARK: - Station model

/// Presentational + behavioural model for a single radio station.
/// Built from static data + API genre/decade lists in RadioStationData builders.
struct RadioStation: Identifiable, Sendable {
    let id: String
    let name: String
    /// Short descriptor: "your entire library", "42 tracks", etc.
    let description: String
    /// Passed verbatim as the `type` query param to GET /api/library/radio.
    let filterType: String
    /// Passed as `value` query param; nil for type-only stations (all / workout / etc.).
    let filterValue: String?
    /// Minimum required tracks — fewer shows an error toast rather than starting playback.
    let minTracks: Int
    /// Built from learned moods, so only playable where the server has vibe embeddings.
    var needsMoods = false
}

// MARK: - Station data

enum RadioStationData {

    /// Mood, wildcard and workout stations play every matching song however few, so one is enough.
    static let stationMinTracks = 1

    // MARK: Static stations (Quick Start)

    static let staticStations: [RadioStation] = [
        RadioStation(
            id: "all", name: "shuffle all", description: "your entire library", filterType: "all", filterValue: nil, minTracks: 10
        ),
        RadioStation(
            id: "workout", name: "workout", description: "high energy tracks", filterType: "workout", filterValue: nil,
            minTracks: stationMinTracks, needsMoods: true
        ),
        RadioStation(
            id: "discovery", name: "discovery", description: "tracks you rarely play", filterType: "discovery", filterValue: nil, minTracks: 20
        ),
        RadioStation(
            id: "favorites", name: "favorites", description: "most played", filterType: "favorites", filterValue: nil, minTracks: 10
        ),
    ]

    // MARK: Builders

    /// Mood stations in the server's order. The server's name is shown as-is; views lowercase it.
    static func buildMoodStations(from stations: [MoodStationInfo]) -> [RadioStation] {
        stations.map { s in
            RadioStation(
                id: "mood-\(s.value)",
                name: s.name,
                description: s.description,
                filterType: "mood",
                filterValue: s.value,
                minTracks: stationMinTracks,
                needsMoods: true
            )
        }
    }

    /// The stations this server can play: mood-built ones only where vibe embeddings exist.
    static func playable(_ stations: [RadioStation], moodsAvailable: Bool) -> [RadioStation] {
        moodsAvailable ? stations : stations.filter { !$0.needsMoods }
    }

    /// Genre stations: all genres from the API that pass the caller's filter (count ≥ 15).
    static func buildGenreStations(from genres: [RadioGenre]) -> [RadioStation] {
        genres.map { g in
            RadioStation(
                id: "genre-\(g.genre)",
                name: g.genre,
                description: "\(g.count) \(g.count == 1 ? "track" : "tracks")",
                filterType: "genre",
                filterValue: g.genre,
                minTracks: 15
            )
        }
    }

    /// Decade stations: one per decade in the API response.
    static func buildDecadeStations(from decades: [RadioDecade]) -> [RadioStation] {
        decades.map { d in
            RadioStation(
                id: "decade-\(d.decade)",
                name: decadeLabel(d.decade),
                description: "\(d.count) \(d.count == 1 ? "track" : "tracks")",
                filterType: "decade",
                filterValue: "\(d.decade)",
                minTracks: 15
            )
        }
    }

    // MARK: Helpers

    /// Decade label per §3.4 of 10-home-radio-collection.md:
    ///   < 1900  → "1700s"
    ///   1900–1999 → "80s", "90s" (two-digit suffix)
    ///   ≥ 2000  → "2000s", "2010s"
    static func decadeLabel(_ decade: Int) -> String {
        if decade < 1900 { return "\(decade)s" }
        if decade < 2000 { return "\(decade % 100)s" }
        return "\(decade)s"
    }
}
