import Foundation

// MARK: - Stats response: shelf and spoken sections

struct ShelfStats: Codable, Sendable {
    let tracks: CountPair
    let albums: CountPair
    let artists: CountPair
    let analysis: AnalysisCounts
    let neverPlayed: Int
    let decades: [DecadeRow]
}

struct CountPair: Codable, Sendable { let total: Int; let heard: Int }
struct AnalysisCounts: Codable, Sendable { let done: Int; let pending: Int; let failed: Int; let total: Int }
struct DecadeRow: Codable, Sendable, Identifiable { let decade: Int; let albums: Int; let heard: Int; var id: Int { decade } }

struct SpokenStats: Codable, Sendable {
    let audiobooks: AudiobookStats
    let podcasts: PodcastStats
}

struct AudiobookStats: Codable, Sendable {
    let seconds: Double
    let finished: Int
    let inProgress: Int
    let setAside: Int
    let topAuthors: [AuthorSeconds]
    let current: NowReading?
}

struct AuthorSeconds: Codable, Sendable, Identifiable { let name: String; let seconds: Double; var id: String { name } }
struct NowReading: Codable, Sendable { let title: String; let author: String?; let percent: Double }

struct PodcastStats: Codable, Sendable {
    let seconds: Double
    let finished: Int
    let inProgress: Int
    let subscriptions: Int
    let backlog: Int
}
