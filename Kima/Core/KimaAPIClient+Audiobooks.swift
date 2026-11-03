import Foundation

// MARK: - Internal Decodable helper for polymorphic GET /audiobooks response

/// The list endpoint returns either a JSON array of `Audiobook`, or `{ "configured": false, ... }` when
/// Audiobookshelf is not set up. JSONDecoder cannot decode "array or object" directly, so this tries the
/// unkeyed (array) container first and falls back to the keyed (object) shape.
private struct AudiobookListDecoded: Decodable {
    let result: AudiobookListResult

    init(from decoder: Decoder) throws {
        // Attempt array decode first (the normal configured-and-populated case).
        // If the JSON root is an object, unkeyedContainer() throws and we fall through.
        if var uc = try? decoder.unkeyedContainer() {
            var books: [Audiobook] = []
            if let count = uc.count { books.reserveCapacity(count) }
            while !uc.isAtEnd {
                books.append(try uc.decode(Audiobook.self))
            }
            result = .configured(books)
            return
        }
        // Object shape: { configured: false, ... }
        let kc = try decoder.container(keyedBy: ObjectKeys.self)
        let configured = try kc.decodeIfPresent(Bool.self, forKey: .configured) ?? true
        result = configured ? .configured([]) : .notConfigured
    }

    private enum ObjectKeys: String, CodingKey { case configured }
}

// MARK: - Private request payloads

private struct AudiobookProgressPayload: Encodable {
    let currentTime: Double
    let duration: Double
    let isFinished: Bool
}


// MARK: - KimaAPIClient + Audiobooks

extension KimaAPIClient {

    // MARK: Library

    /// GET /api/audiobooks
    ///
    /// Returns `.configured([Audiobook])` normally.
    /// Returns `.notConfigured` when the server responds with `{ configured: false }`.
    func getAudiobooks() async throws -> AudiobookListResult {
        let decoded: AudiobookListDecoded = try await get("/audiobooks", authed: true)
        return decoded.result
    }

    /// GET /api/audiobooks/:id
    ///
    /// Returns the full audiobook including `sections`, `tracks`, and `progress`.
    /// Sections may be nil if the book has none; tracks may be nil for single-file books.
    func getAudiobook(id: String) async throws -> Audiobook {
        try await get("/audiobooks/\(id)", authed: true)
    }

    /// GET /api/audiobooks/series/:seriesName
    ///
    /// Returns all books in a series, ordered by `seriesSequence`. The name is encoded as one path segment.
    func getAudiobooksBySeries(seriesName: String) async throws -> [Audiobook] {
        let encoded = KimaServer.pathSegment(seriesName)
        return try await get("/audiobooks/series/\(encoded)", authed: true)
    }

    /// GET /api/audiobooks/continue-listening — recent in-progress entries (max 10, newest first).
    /// Returns `[]` when Audiobookshelf is not configured.
    func getContinueListeningAudiobooks() async throws -> [AudiobookContinueItem] {
        try await get("/audiobooks/continue-listening", authed: true)
    }

    // MARK: Sync

    /// POST /api/audiobooks/sync
    ///
    /// Triggers a re-sync from Audiobookshelf. May take several seconds.
    /// Response: `{ success: Bool, result: { synced, failed, skipped, errors[] } }`.
    @discardableResult
    func syncAudiobooks() async throws -> AudiobookSyncResponse {
        try await postJSON("/audiobooks/sync", body: EmptyRequestBody(), authed: true)
    }

    // MARK: Progress

    /// POST /api/audiobooks/:id/progress — saves book-absolute progress and syncs it back to Audiobookshelf.
    /// Call every 15 s while playing and on pause, background, and end-of-book.
    /// This is the dedicated progress endpoint, not `/api/playback-state`.
    @discardableResult
    func saveAudiobookProgress(
        bookId: String,
        currentTime: Double,
        duration: Double,
        isFinished: Bool
    ) async throws -> AudiobookProgressSaveResponse {
        let payload = AudiobookProgressPayload(
            currentTime: currentTime,
            duration: duration,
            isFinished: isFinished
        )
        return try await postJSON("/audiobooks/\(bookId)/progress", body: payload, authed: true)
    }

    /// DELETE /api/audiobooks/:id/progress
    ///
    /// Resets progress for a book (user-initiated "Reset Progress" or "Listen Again" action).
    func deleteAudiobookProgress(bookId: String) async throws {
        try await deleteChecked("/audiobooks/\(bookId)/progress", authed: true)
    }
}
