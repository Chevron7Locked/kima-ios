import Foundation

// MARK: - Stats response (GET /api/stats): window, listening
//
// Wire shape of GET /api/stats. `system` is admin-only and deliberately not modelled on
// iOS. Plain typed Codable with no leniency: a shape mismatch lands the page in its
// "couldn't load" state.

/// Rolling windows, so early in a month or week there is no near-empty cliff
enum StatsPeriod: String, Codable, Sendable, CaseIterable, Identifiable {
    case d30 = "30d"
    case m12 = "12mo"
    case all = "all"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .d30: return "30 days"
        case .m12: return "12 months"
        case .all: return "all time"
        }
    }
    /// The clause appended to "about N hours of music …".
    var sentence: String {
        switch self {
        case .d30: return "last 30 days"
        case .m12: return "last 12 months"
        case .all: return ""
        }
    }
}

struct StatsResponse: Codable, Sendable {
    /// Echoed back by the server, so the page renders the window it was given.
    let period: String
    let listening: ListeningStats
    let shelf: ShelfStats
    let spoken: SpokenStats
    let signature: Signature
}

struct ListeningStats: Codable, Sendable {
    let plays: Int
    /// Derived from track length, never measured. Always shown as "about".
    let estimatedSeconds: Double
    let distinctTracks: Int
    let distinctArtists: Int
    let distinctAlbums: Int
    let firstPlay: String?
    let lastPlay: String?
    let bySource: [String: Int]
    /// [weekday 0=Sunday][hour 0-23], in the viewer's own timezone.
    let clock: [[Int]]
    let peak: StatsPeak?
    /// Valence on x, energy on y, both bucketed 1..24.
    let shape: [ShapePoint]
    let drift: [DriftPoint]
    let topArtists: [TopArtist]
    let topTracks: [TopTrack]
}

struct StatsPeak: Codable, Sendable { let weekday: Int; let hour: Int; let plays: Int }
struct ShapePoint: Codable, Sendable { let x: Int; let y: Int; let plays: Int }
struct DriftPoint: Codable, Sendable, Identifiable {
    let month: String
    let energy: Double?
    let valence: Double?
    let bpm: Double?
    let plays: Int
    var id: String { month }
}
struct TopArtist: Codable, Sendable, Identifiable { let id: String; let name: String; let plays: Int }
struct TopTrack: Codable, Sendable, Identifiable { let id: String; let title: String; let artist: String; let plays: Int }
