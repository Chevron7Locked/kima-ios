import Foundation

// MARK: - Vibe Map models (GET /api/vibe/map)

/// One track on the 3-D map returned by GET /api/vibe/map, each axis scaled to 0–1. `artist` is a flat name
/// string. `moods` and `dominantMood` use the server's mood column names (`moodHappy`, …); `dominantMood` can also
/// be "neutral" or "unanalyzed". A bare axis name is mapped by `VibeMoodPalette.paletteKey(forAxis:)`.
struct VibeMapTrack: Codable, Sendable, Identifiable {
    let id: String
    let x: Double
    let y: Double
    /// Height in the 3-D map. A server from before the 3-D layout omits it; 0.5 draws it flat.
    let z: Double
    let title: String
    /// Flat artist name string — not a nested artist object. Matches the
    /// denormalised field returned by the map projection service.
    let artist: String
    let artistId: String
    let albumId: String
    let coverUrl: String?
    let dominantMood: String
    let moodScore: Double
    /// All mood scores for this track, keyed by mood field name.
    let moods: [String: Double]
    let energy: Double?
    let valence: Double?
    /// Place on the logo gradient, 0 azure to 1 amber. Absent on servers without the colour field.
    let colour: Double?

    init(
        id: String, x: Double, y: Double, z: Double = 0.5, title: String, artist: String,
        artistId: String, albumId: String, coverUrl: String?, dominantMood: String,
        moodScore: Double, moods: [String: Double], energy: Double?, valence: Double?,
        colour: Double? = nil
    ) {
        self.id = id; self.x = x; self.y = y; self.z = z; self.title = title; self.artist = artist
        self.artistId = artistId; self.albumId = albumId; self.coverUrl = coverUrl
        self.dominantMood = dominantMood; self.moodScore = moodScore; self.moods = moods
        self.energy = energy; self.valence = valence; self.colour = colour
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            x: try c.decode(Double.self, forKey: .x),
            y: try c.decode(Double.self, forKey: .y),
            z: try c.decodeIfPresent(Double.self, forKey: .z) ?? 0.5,
            title: try c.decode(String.self, forKey: .title),
            artist: try c.decode(String.self, forKey: .artist),
            artistId: try c.decode(String.self, forKey: .artistId),
            albumId: try c.decode(String.self, forKey: .albumId),
            coverUrl: try c.decodeIfPresent(String.self, forKey: .coverUrl),
            dominantMood: try c.decode(String.self, forKey: .dominantMood),
            moodScore: try c.decode(Double.self, forKey: .moodScore),
            moods: try c.decode([String: Double].self, forKey: .moods),
            energy: try c.decodeIfPresent(Double.self, forKey: .energy),
            valence: try c.decodeIfPresent(Double.self, forKey: .valence),
            colour: try c.decodeIfPresent(Double.self, forKey: .colour)
        )
    }
}

/// Response envelope for GET /api/vibe/map. `moodSignature` changes when track moods change without the track
/// count changing; with `computedAt` (ISO-8601, for spotting stale cache hits) and `trackCount` it identifies one
/// layout. Servers that still send the old `sampled` flag are fine: unknown keys are ignored.
struct VibeMapResponse: Codable, Sendable {
    let tracks: [VibeMapTrack]
    let trackCount: Int
    let computedAt: String
    let moodSignature: String?
}

/// Outcome of `GET /api/vibe/map`. The server answers 202 `{computing:true}` while a big library's map is first
/// laid out in the background, and 200 with the full payload once ready. Callers treat `.computing` as "not yet":
/// poll, never an error.
enum VibeMapOutcome: Sendable {
    case ready(VibeMapResponse)
    case computing
}

// MARK: - Vibe Path models (POST /api/vibe/path)

/// One track node inside a generated song-path journey. All fields are flat (no nested album/artist objects):
/// the path service JOINs and denormalises before responding.
struct VibePathTrack: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let duration: Double
    let albumId: String
    let albumTitle: String
    let albumCoverUrl: String?
    let artistId: String
    let artistName: String
}

/// Response envelope for POST /api/vibe/path. `path` holds only the in-between waypoints; `startTrack` and
/// `endTrack` are the request's anchors. Full playback order: [startTrack] + path + [endTrack].
struct VibePathResponse: Codable, Sendable {
    struct Metadata: Codable, Sendable {
        /// Total track count including start, waypoints, and end.
        let totalTracks: Int
        /// Cosine distance between start and end CLAP embeddings (0–2).
        let embeddingDistance: Double
        /// Mean cosine distance between consecutive path steps.
        let averageStepSize: Double
        /// "smooth" or "discovery" — mirrors the mode sent in the request.
        let mode: String
    }
    let startTrack: VibePathTrack
    let endTrack: VibePathTrack
    let path: [VibePathTrack]
    let metadata: Metadata
}

// MARK: - Shared result track (alchemy + search)

/// Track returned by POST /api/vibe/alchemy, POST /api/vibe/search and GET /api/vibe/similar/:trackId. Carries
/// `distance` and `similarity`, which the base `Track` lacks. `trackNo` is optional because search and similar return
/// it and alchemy does not.
struct VibeResultTrack: Codable, Sendable, Identifiable {
    struct Album: Codable, Sendable {
        let id: String
        let title: String
        let coverUrl: String?
    }
    struct Artist: Codable, Sendable {
        let id: String
        let name: String
    }
    let id: String
    let title: String
    let duration: Double
    let trackNo: Int?
    /// Raw cosine distance from the query vector (0–2; lower = more similar).
    let distance: Double?
    /// Similarity score in [0, 1]: `1 − distance` (or re-ranked score for search).
    let similarity: Double?
    let album: Album
    let artist: Artist
}

// MARK: - Alchemy response (POST /api/vibe/alchemy)

/// Response envelope for POST /api/vibe/alchemy. Alchemy returns the nearest tracks to
/// `mean(add embeddings) − mean(subtract embeddings)`; there is no single source track, so no `sourceTrackId`.
struct VibeAlchemyResponse: Codable, Sendable {
    let tracks: [VibeResultTrack]
}

// MARK: - Search response (POST /api/vibe/search)

/// Response envelope for POST /api/vibe/search. Unknown keys the server may still send are ignored.
struct VibeSearchResponse: Codable, Sendable {
    /// The trimmed query string as echoed by the server.
    let query: String
    let tracks: [VibeResultTrack]
}
