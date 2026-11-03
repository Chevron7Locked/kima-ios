import Foundation
import os

// Codable shapes for Kima library entities: Track, Album, Artist and their nested types.
// Shapes mirror the server's TypeScript interfaces.
// JSON keys are camelCase — the live TS backend format.

// MARK: - Track nested refs

/// Embedded artist stub on a Track. All fields optional — the server may omit them on
/// lightweight list responses.
struct TrackArtistRef: Codable, Sendable {
    let id: String?
    let name: String?
}

/// Embedded album stub on a Track. Carries the cover-art identifier used by CoverArtURL, and the
/// album's artist, which library and search track lists send in place of a track-level artist.
struct TrackAlbumRef: Codable, Sendable {
    let id: String?
    let title: String?
    let coverArt: String?
    var artist: TrackArtistRef? = nil
}

// MARK: - Audio features (vibe mode)

/// Perceptual audio analysis fields stored on a track. All optional — the server populates
/// them only after the analyzer has run on the track.
struct AudioFeatures: Codable, Sendable, Equatable {
    let bpm: Double?
    let energy: Double?
    let valence: Double?
    let arousal: Double?
    let danceability: Double?
    let keyScale: String?
    let instrumentalness: Double?
    let moodHappy: Double?
    let moodSad: Double?
    let moodRelaxed: Double?
    let moodAggressive: Double?
    let moodParty: Double?
    let moodAcoustic: Double?
    let moodElectronic: Double?
    let analysisMode: String?
}

// MARK: - Track

/// A single music track. `duration` is in seconds (from the TS backend).
struct Track: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let duration: Double                // seconds — required in the TS spec
    let trackNo: Int?
    let trackNumber: Int?               // alias used on some responses alongside trackNo
    let discNumber: Int?
    let discSubtitle: String?
    let isMissing: Bool?
    let previewUrl: String?
    let playCount: Int?
    let userPlayCount: Int?
    let listeners: Int?
    /// The track's own artist as sent; read `artist`, which falls back to the album's.
    let trackArtist: TrackArtistRef?
    let album: TrackAlbumRef?
    // Metadata-override fields (set via PUT /enrichment or /library/tracks/:id/metadata)
    let displayTitle: String?
    let displayTrackNo: Int?
    let hasUserOverrides: Bool?
    /// Audio features for vibe match-score computation. Nil unless the library response
    /// includes them (not yet populated on all endpoints — vibe badge is best-effort).
    let audioFeatures: AudioFeatures?

    /// Title to display: user override when set, else the server title.
    var effectiveTitle: String { displayTitle ?? title }

    /// The track's artist, else its album's artist (library and search lists send only the album's).
    var artist: TrackArtistRef? { trackArtist ?? album?.artist }

    private enum CodingKeys: String, CodingKey {
        case id, title, duration, trackNo, trackNumber, discNumber, discSubtitle, isMissing, previewUrl
        case playCount, userPlayCount, listeners, album, displayTitle, displayTrackNo, hasUserOverrides
        case audioFeatures
        case trackArtist = "artist"
    }
}

extension Track {
    /// A track built in code: every field the caller doesn't pass is nil.
    init(
        id: String, title: String, duration: Double,
        trackNo: Int? = nil, trackNumber: Int? = nil, isMissing: Bool? = nil, previewUrl: String? = nil,
        artist: TrackArtistRef? = nil, album: TrackAlbumRef? = nil
    ) {
        self.init(
            id: id, title: title, duration: duration,
            trackNo: trackNo, trackNumber: trackNumber, discNumber: nil, discSubtitle: nil,
            isMissing: isMissing, previewUrl: previewUrl, playCount: nil, userPlayCount: nil, listeners: nil,
            trackArtist: artist, album: album,
            displayTitle: nil, displayTrackNo: nil, hasUserOverrides: nil, audioFeatures: nil
        )
    }
}

extension Track {
    /// Album play order: disc, then track number; tracks with no number go last.
    static func albumOrder(_ a: Track, _ b: Track) -> Bool {
        let aDisc = a.discNumber ?? 1, bDisc = b.discNumber ?? 1
        if aDisc != bDisc { return aDisc < bDisc }
        return (a.trackNumber ?? a.trackNo ?? Int.max) < (b.trackNumber ?? b.trackNo ?? Int.max)
    }
}

// MARK: - Album nested types

/// Embedded artist ref on an Album. Carries mbid for download-resolution (rgMbid ?? mbid).
struct AlbumArtistRef: Codable, Sendable {
    let id: String?
    let mbid: String?
    let name: String?
}

/// A track slot that exists in the release but is not in the library (preview-only row).
struct MissingTrack: Codable, Sendable {
    let title: String
    let trackNumber: Int?
    let previewUrl: String?
}

/// Lightweight album used inside `Artist.similarAlbums` and `Album.similarAlbums` carousels.
struct SimilarAlbum: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let artist: AlbumArtistRef?
    let coverArt: String?
    let coverUrl: String?
    let year: Int?
    let owned: Bool?
    let mbid: String?
}

// MARK: - Album

/// A music album returned from GET /library/albums or GET /library/albums/:id.
/// The full detail response includes `tracks`, `missingTracks`, `similarAlbums`; list
/// responses omit them. All nested fields are optional so the same struct decodes both.
struct Album: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let artist: AlbumArtistRef?
    let year: Int?
    let genre: String?
    let genres: [String]?
    let coverArt: String?
    let coverUrl: String?
    let duration: Double?
    let trackCount: Int?
    let songCount: Int?
    let playCount: Int?
    let type: String?
    let mbid: String?
    let rgMbid: String?
    let owned: Bool?
    let availability: String?
    let lastSynced: String?
    // Lenient: one bad track shouldn't fail an owned album's decode (see LossyArray below).
    @LossyArray var tracks: [Track]?
    let missingTracks: [MissingTrack]?
    let similarAlbums: [SimilarAlbum]?
    // Metadata-override fields
    let displayTitle: String?
    let displayYear: Int?
    let userCoverUrl: String?
    let userGenres: [String]?
    let hasUserOverrides: Bool?

    /// Title to display: user override when set, else the server title.
    var effectiveTitle: String { displayTitle ?? title }

    /// The album's own tracks in play order (disc, then track). Every play and queue of an album uses it.
    var tracksInOrder: [Track] { (tracks ?? []).sorted(by: Track.albumOrder) }
}

// MARK: - Artist nested types

/// Lightweight artist from GET /library/artists/:id `similarArtists` array.
/// `weight` is a relatedness score used to compute match percentage in the UI.
struct SimilarArtist: Codable, Sendable, Identifiable {
    let id: String
    let mbid: String?
    let name: String
    let coverArt: String?
    let image: String?
    let albumCount: Int?
    let ownedAlbumCount: Int?
    let weight: Double?
    let inLibrary: Bool?
}

// MARK: - Artist

/// A music artist returned from GET /library/artists or GET /library/artists/:id.
/// The full detail response includes `albums`, `topTracks`, `similarArtists`; list
/// responses omit them.
struct Artist: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let coverArt: String?
    let image: String?
    let heroUrl: String?
    let bio: String?
    let summary: String?
    let mbid: String?
    let url: String?
    let listeners: Int?
    let genres: [String]?
    let tags: [String]?
    // Count fields returned by list endpoints.
    // These are optional — the list endpoint may or may not populate them.
    let albumCount: Int?
    let trackCount: Int?
    // Lenient: a single malformed album/track/similar-artist is skipped rather than failing
    // the whole artist decode (see LossyArray below). Public type stays `[T]?`.
    @LossyArray var albums: [Album]?
    @LossyArray var topTracks: [Track]?
    @LossyArray var similarArtists: [SimilarArtist]?
    // Metadata-override fields
    let displayName: String?
    let userSummary: String?
    let userHeroUrl: String?
    let userGenres: [String]?
    let hasUserOverrides: Bool?

    /// Name to display: user override when set, else the server name.
    var effectiveName: String { displayName ?? name }

    private enum CodingKeys: String, CodingKey {
        case id, name, coverArt, image, heroUrl, bio, summary, mbid, url, listeners
        case genres, tags, albumCount, trackCount, albums, topTracks, similarArtists
        case displayName, userSummary, userHeroUrl, userGenres, hasUserOverrides
    }

    // Custom decode only to make `id` tolerant: the discovery endpoint (`/artists/discover/:id`) returns a
    // not-owned artist with no `id`, which made the synthesized decoder throw keyNotFound. A stable id is
    // synthesized from mbid, then name. Library artists carry a real `id`, so this is a no-op for them.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mbidValue = try c.decodeIfPresent(String.self, forKey: .mbid)
        let nameValue = try c.decode(String.self, forKey: .name)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? mbidValue ?? nameValue
        self.name = nameValue
        self.coverArt = try c.decodeIfPresent(String.self, forKey: .coverArt)
        self.image = try c.decodeIfPresent(String.self, forKey: .image)
        self.heroUrl = try c.decodeIfPresent(String.self, forKey: .heroUrl)
        self.bio = try c.decodeIfPresent(String.self, forKey: .bio)
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary)
        self.mbid = mbidValue
        self.url = try c.decodeIfPresent(String.self, forKey: .url)
        self.listeners = try c.decodeIfPresent(Int.self, forKey: .listeners)
        self.genres = try c.decodeIfPresent([String].self, forKey: .genres)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags)
        self.albumCount = try c.decodeIfPresent(Int.self, forKey: .albumCount)
        self.trackCount = try c.decodeIfPresent(Int.self, forKey: .trackCount)
        self._albums = try c.decode(LossyArray<Album>.self, forKey: .albums)
        self._topTracks = try c.decode(LossyArray<Track>.self, forKey: .topTracks)
        self._similarArtists = try c.decode(LossyArray<SimilarArtist>.self, forKey: .similarArtists)
        self.displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        self.userSummary = try c.decodeIfPresent(String.self, forKey: .userSummary)
        self.userHeroUrl = try c.decodeIfPresent(String.self, forKey: .userHeroUrl)
        self.userGenres = try c.decodeIfPresent([String].self, forKey: .userGenres)
        self.hasUserOverrides = try c.decodeIfPresent(Bool.self, forKey: .hasUserOverrides)
    }
}

// MARK: - Lenient array decoding
// Keeps one malformed nested element from failing a whole response decode, so one bad album, track or
// similar-artist doesn't blank the screen. The wrapped value stays `[Element]?`.

/// A `Codable` array property wrapper that SKIPS elements which fail to decode instead of failing
/// the whole container. Missing / `null` keys decode to `nil` (see the `KeyedDecodingContainer`
/// overload) and are omitted on encode (see the `KeyedEncodingContainer` overload), exactly
/// matching the plain `[Element]?` behaviour it replaces.
@propertyWrapper
struct LossyArray<Element: Codable & Sendable>: Codable, Sendable {
    var wrappedValue: [Element]?

    init(wrappedValue: [Element]?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        // Decode as an array of never-throwing element wrappers, then drop the failures.
        let raw = try [FailableDecodable<Element>](from: decoder)
        let kept = raw.compactMap(\.value)
        let skipped = raw.count - kept.count
        if skipped > 0 {
            LossyDecodeLog.record(skipped: skipped, kept: kept.count, element: "\(Element.self)")
        }
        wrappedValue = kept
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    /// Absent or `null` keys yield `LossyArray(wrappedValue: nil)` rather than throwing, so a
    /// property-wrapped `LossyArray` behaves like the optional array it replaces.
    func decode<Element>(_ type: LossyArray<Element>.Type, forKey key: Key) throws -> LossyArray<Element> {
        try decodeIfPresent(type, forKey: key) ?? LossyArray(wrappedValue: nil)
    }
}

extension KeyedDecodingContainer {
    /// A required list that drops rows which fail to decode; a missing or `null` key still throws.
    func decodeLossyList<Element: Codable & Sendable>(_ type: Element.Type, forKey key: Key) throws -> [Element] {
        guard let list = try decodeIfPresent(LossyArray<Element>.self, forKey: key)?.wrappedValue else {
            throw DecodingError.valueNotFound([Element].self, .init(
                codingPath: codingPath + [key], debugDescription: "missing \(key.stringValue)"))
        }
        return list
    }
}

extension KeyedEncodingContainer {
    /// A `nil` wrapped value is omitted entirely (no key written), matching `[Element]?`.
    mutating func encode<Element>(_ value: LossyArray<Element>, forKey key: Key) throws {
        try encodeIfPresent(value.wrappedValue, forKey: key)
    }
}

/// Records lossy-decode skips to the unified log (subsystem `com.chevron7locked.kima`, category
/// `lossy-decode`), visible on-device via Console / `log collect`. Skips happen on an otherwise
/// successful decode, so they are logged here rather than to the artist-load error breadcrumb
/// (which records hard load failures) — keeping model decoding decoupled from the file store.
enum LossyDecodeLog {
    private static let logger = Logger(subsystem: "com.chevron7locked.kima", category: "lossy-decode")

    static func record(skipped: Int, kept: Int, element: String) {
        logger.warning("lossyarray<\(element, privacy: .public)> skipped \(skipped, privacy: .public) malformed element(s); kept \(kept, privacy: .public)")
    }
}
