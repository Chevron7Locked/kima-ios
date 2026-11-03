import Foundation

// MARK: - Stats response: signature section and its drill-ins

struct Signature: Codable, Sendable {
    let concentration: Concentration?
    let albumHabit: AlbumHabit?
    let era: Era?
    let key: KeyStats?
    let ownedVsPlayed: [OwnedRow]
    /// The same, hour by hour, for a curve rather than four bars.
    let hourly: [HourPoint]
}

struct Concentration: Codable, Sendable { let forHalf: Int; let forEighty: Int; let distinct: Int }
struct AlbumHabit: Codable, Sendable { let moves: Int; let sameAlbumPct: Double; let inOrderPct: Double }
struct Era: Codable, Sendable { let medianYear: Int; let buckets: [EraBucket] }
struct EraBucket: Codable, Sendable, Identifiable { let label: String; let plays: Int; let percent: Double; var id: String { label } }
struct KeyStats: Codable, Sendable {
    let minorPct: Double
    let top: [KeyPlays]
    /// Every key played, for the wheel. `key` is the pitch, e.g. "F#".
    let all: [KeyScalePlays]
}
/// One row per pitch and scale, as the server sends it (`key` is the bare pitch).
struct KeyScalePlays: Codable, Sendable, Identifiable {
    let key: String; let scale: String; let plays: Int
    var id: String { "\(key)|\(scale)" }
}
struct KeyPlays: Codable, Sendable, Identifiable { let key: String; let plays: Int; var id: String { key } }
struct OwnedRow: Codable, Sendable, Identifiable { let label: String; let owned: Double; let played: Double; let unit: String; var id: String { label } }
struct HourPoint: Codable, Sendable, Identifiable { let hour: Int; let plays: Int; let energy: Double; var id: Int { hour } }

/// GET /stats/hour — what was playing in one cell of the week.
struct HourDetail: Codable, Sendable {
    let weekday: Int
    let hour: Int
    let listens: Int
    let tracks: [HourTrack]
    let artists: [NamedListens]
    /// The most recent time this hour came round and something played.
    let lastAt: String?
}
struct HourTrack: Codable, Sendable, Identifiable {
    let title: String; let artist: String; let listens: Int
    var id: String { "\(artist)|\(title)" }
}
struct NamedListens: Codable, Sendable, Identifiable { let name: String; let listens: Int; var id: String { name } }

/// GET /stats/region — what sits at one point of the taste plot.
struct RegionDetail: Codable, Sendable {
    let x: Int
    let y: Int
    let listens: Int
    let tracks: [HourTrack]
    let energy: Double?
    let valence: Double?
    let bpm: Double?
}

/// GET /stats/tracks — a slice of the page as playable tracks (of=top|never|core|key|decade).
struct PlayableSliceResponse: Codable, Sendable { let tracks: [Track] }

/// GET /stats/track/:id/plays — the count for the player bar line.
struct TrackPlaysResponse: Codable, Sendable { let plays: Int }
