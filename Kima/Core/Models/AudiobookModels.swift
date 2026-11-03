import Foundation

// MARK: - Audiobook (verbatim from the server's types)

struct Audiobook: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let author: String
    let narrator: String?
    let description: String?
    /// Relative path — pass to `getCoverArtUrl()` or load via `/api/audiobooks/:id/cover`.
    let coverUrl: String?
    /// Book-absolute duration in seconds (sum of all files).
    let duration: Double
    let libraryId: String?
    let publisher: String?
    let publishedYear: String?
    let genres: [String]?
    let series: AudiobookSeries?
    let isbn: String?
    let asin: String?
    let language: String?
    let progress: AudiobookProgress?
    /// nil if single-file or not yet fetched. Used by BookSession.
    let tracks: [AudiobookTrack]?
    let trackCount: Int?
    /// Chapter markers; nil if none. Capped at 50 for display.
    let sections: [AudiobookSection]?
}

// MARK: - AudiobookProgress

/// Progress entry embedded in Audiobook (from both list and detail responses).
typealias AudiobookProgress = LongFormProgress

// MARK: - AudiobookSection

struct AudiobookSection: Identifiable, Codable, Sendable {
    let index: Int          // 1-based: the server numbers chapters from 1
    let title: String       // chapter name
    /// Book-absolute start time in seconds.
    let start: Double
    // No `end` — use next section.start or book.duration.
    var id: Int { index }
}

// MARK: - AudiobookTrack

struct AudiobookTrack: Identifiable, Codable, Sendable {
    /// 1-based file index (passed to `StreamURL.audiobook` as `index`).
    let index: Int
    /// Book-absolute seconds where this file begins.
    let startOffset: Double
    let duration: Double
    var id: Int { index }
}

// MARK: - AudiobookSeries

struct AudiobookSeries: Codable, Sendable {
    let name: String
    let sequence: String    // "1", "1.5", "2", etc.
}

// MARK: - Continue Listening

/// Shape returned by GET /api/audiobooks/continue-listening.
/// This is a progress entry with cached metadata, not a full Audiobook object.
struct AudiobookContinueItem: Identifiable, Codable, Sendable {
    /// Matches `Audiobook.id` (the Audiobookshelf ID stored as audiobookshelfId in Prisma).
    let id: String
    let title: String
    let author: String
    let coverUrl: String?
    let currentTime: Double
    let duration: Double
    let isFinished: Bool
    let lastPlayedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id = "audiobookshelfId"
        case title, author, coverUrl, currentTime, duration, isFinished, lastPlayedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self,  forKey: .id)
        title       = try c.decode(String.self,  forKey: .title)
        author      = try c.decode(String.self,  forKey: .author)
        coverUrl    = try c.decodeIfPresent(String.self, forKey: .coverUrl)
        currentTime = try c.decode(Double.self,  forKey: .currentTime)
        duration    = try c.decode(Double.self,  forKey: .duration)
        isFinished  = try c.decode(Bool.self,    forKey: .isFinished)
        let raw     = try c.decode(String.self,  forKey: .lastPlayedAt)
        lastPlayedAt = Formatters.parseISO8601OrDistantPast(raw)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,          forKey: .id)
        try c.encode(title,       forKey: .title)
        try c.encode(author,      forKey: .author)
        try c.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try c.encode(currentTime, forKey: .currentTime)
        try c.encode(duration,    forKey: .duration)
        try c.encode(isFinished,  forKey: .isFinished)
        try c.encode(Formatters.iso8601Fractional.string(from: lastPlayedAt), forKey: .lastPlayedAt)
    }

    /// Progress percentage (0–100) derived from `currentTime` / `duration`.
    /// Returns `nil` when `duration` is zero to avoid division by zero.
    var progressPct: Double? { duration > 0 ? currentTime / duration * 100 : nil }
}

// MARK: - Audiobook list result

/// Handles the polymorphic GET /api/audiobooks response:
/// - Normal: flat JSON array of Audiobook objects
/// - Not configured: `{ configured: false, enabled: false, audiobooks: [] }`
enum AudiobookListResult: Sendable {
    case configured([Audiobook])
    case notConfigured
}

// MARK: - Sync

struct AudiobookSyncResult: Codable, Sendable {
    let synced: Int?
    let failed: Int?
    let skipped: Int?
    let errors: [String]?
}

struct AudiobookSyncResponse: Codable, Sendable {
    let success: Bool
    let result: AudiobookSyncResult?
}

// MARK: - Progress save response

struct AudiobookProgressSaveResponse: Codable, Sendable {
    let success: Bool
    let progress: ProgressBody?

    struct ProgressBody: Codable, Sendable {
        let currentTime: Double
        let progress: Double
        let isFinished: Bool
    }
}

// MARK: - Optimistic update helpers

extension Audiobook {
    func withProgress(_ p: AudiobookProgress?) -> Audiobook {
        Audiobook(
            id: id, title: title, author: author, narrator: narrator,
            description: description, coverUrl: coverUrl, duration: duration,
            libraryId: libraryId, publisher: publisher, publishedYear: publishedYear,
            genres: genres, series: series, isbn: isbn, asin: asin,
            language: language, progress: p, tracks: tracks, trackCount: trackCount,
            sections: sections
        )
    }
}
