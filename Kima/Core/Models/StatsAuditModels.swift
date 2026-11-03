import Foundation

// MARK: - False-starts audit (GET/POST /stats/false-starts*)

struct FalseStartAudit: Codable, Sendable {
    let totalRows: Int
    let totalListens: Int
    let duplicateRows: Int
    /// Rows a merge would actually remove; fewer than `duplicateRows`.
    let collapsibleRows: Int
    let heard: Int
    let skipped: Int
    /// Listens of tracks too short to register a play, reported apart from `skipped`.
    let tooShort: Int
    let unclear: Int
    let earliest: String?
    let tracks: [FalseStartTrack]
    let ignored: [IgnoredTrack]
}

struct FalseStartTrack: Codable, Sendable, Identifiable {
    let trackId: String
    let title: String
    let artist: String
    let durationSeconds: Double
    let requiredSeconds: Double?
    /// Listens that can be proven nobody stayed for.
    let skipped: Int
    /// Listens proven real by how long the records span.
    let heard: Int
    let listens: Int
    let rows: Int
    let shortestRunSeconds: Double?
    let lastAt: String
    var id: String { trackId }
}

struct IgnoredTrack: Codable, Sendable, Identifiable {
    let trackId: String
    let title: String
    let artist: String
    let ignoredAt: String
    var id: String { trackId }
}

/// Action results: collapse/remove report {removed, tracks}, ignore/restore
/// report {ignored}. Each response carries only some keys, so each field
/// decodes absent→0.
struct StatsCountsResponse: Codable, Sendable {
    private(set) var removed: Int = 0
    private(set) var tracks: Int = 0
    private(set) var ignored: Int = 0

    private enum CodingKeys: String, CodingKey { case removed, tracks, ignored }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        removed = try c.decodeIfPresent(Int.self, forKey: .removed) ?? 0
        tracks = try c.decodeIfPresent(Int.self, forKey: .tracks) ?? 0
        ignored = try c.decodeIfPresent(Int.self, forKey: .ignored) ?? 0
    }
}

/// POST bodies for the three list-taking audit actions (cap 2000, server-side).
struct TrackIdsBody: Encodable { let trackIds: [String] }
