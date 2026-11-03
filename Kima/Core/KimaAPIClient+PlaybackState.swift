import Foundation

// MARK: - Compact queue-track shape (server-side sanitised format)

/// Compact track stored inside a PlaybackState queue. The server stores queue items as full track objects and
/// sanitises each to id, title, duration (seconds, Double), artist {id, name}, album {id, title, coverArt}.
/// All nested fields are optional so the Track ↔ QueueTrack JSON round-trip survives null artist/album stubs.
struct QueueTrack: Codable, Sendable {
    let id: String
    let title: String
    let duration: Double

    let artist: QueueArtist?
    let album: QueueAlbum?

    struct QueueArtist: Codable, Sendable {
        let id: String?
        let name: String?
    }

    struct QueueAlbum: Codable, Sendable {
        let id: String?
        let title: String?
        let coverArt: String?
    }
}

extension QueueTrack {
    /// A queue entry for `track`. The artist is the track's own, else its album's: library, search and playlist
    /// lists send only the album's, and the server keeps no album artist, so the restored song would have none.
    init(_ track: Track) {
        self.init(
            id: track.id, title: track.title, duration: track.duration,
            artist: track.artist.map { QueueArtist(id: $0.id, name: $0.name) },
            album: track.album.map { QueueAlbum(id: $0.id, title: $0.title, coverArt: $0.coverArt) }
        )
    }
}

// MARK: - PlaybackState response

/// Server response for GET and POST /api/playback-state (the Prisma PlaybackState row, camelCase JSON).
/// `updatedAt` is decoded as String because JSONDecoder rejects Prisma's fractional-seconds ISO 8601
/// ("2024-01-15T12:00:00.000Z"); PlaybackSyncCoordinator parses it with ISO8601DateFormatter.
struct PlaybackStateResponse: Codable, Sendable {
    let playbackType: String
    let trackId: String?
    let audiobookId: String?
    let podcastId: String?
    /// Queue as stored by the server — array of sanitised track objects, or nil when the
    /// server has no queue for this user.
    let queue: [QueueTrack]?
    let currentIndex: Int
    let isShuffle: Bool
    let updatedAt: String?
}

// MARK: - Save payload

private struct PlaybackStateSavePayload: Encodable {
    let playbackType: String
    let trackId: String?
    let queue: [QueueTrack]
    let currentIndex: Int
    let isShuffle: Bool
}

// MARK: - KimaAPIClient extension

extension KimaAPIClient {

    /// GET /api/playback-state — the saved queue state, or nil when the server has none (it sends JSON `null`).
    /// `Optional<PlaybackStateResponse>` decodes null as `.none`, so the same `get<T>` handles both cases.
    func getPlaybackState() async throws -> PlaybackStateResponse? {
        try await get("/playback-state", authed: true)
    }

    /// POST /api/playback-state — upserts queue/index/shuffle for the current user.
    ///
    /// Returns the saved row (includes `updatedAt`). Callers advance `lastServerSync` from
    /// this response so the next poll ignores our own echo.
    @discardableResult
    func savePlaybackState(
        playbackType: String,
        trackId: String?,
        queue: [QueueTrack],
        currentIndex: Int,
        isShuffle: Bool
    ) async throws -> PlaybackStateResponse {
        let payload = PlaybackStateSavePayload(
            playbackType: playbackType,
            trackId: trackId,
            queue: queue,
            currentIndex: currentIndex,
            isShuffle: isShuffle
        )
        return try await postJSON("/playback-state", body: payload, authed: true)
    }
}
