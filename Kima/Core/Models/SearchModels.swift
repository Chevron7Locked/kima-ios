import Foundation

// MARK: - Discovery result models

/// Polymorphic result from GET /search/discover?type=all. `type` is "music" (external artist), "track"
/// (external track match) or "podcast" (iTunes/Deezer).
/// Unknown future type values decode as `.unknown`.
struct DiscoverResult: Identifiable, Decodable, Sendable {

    enum ResultType: String, Decodable, Sendable {
        case music, track, podcast, unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: raw) ?? .unknown
        }
    }

    let type:      ResultType
    /// External id: iTunes collectionId (a JSON *number*), "deezer:<id>", or nil for music/track.
    let externalId: String?
    let name:      String
    let mbid:      String?
    let image:     String?
    let listeners: Int?

    /// Stable `Identifiable` id: mbid → externalId → name.
    var id: String { mbid ?? externalId ?? name }

    /// The id to navigate to artist detail with. Treats an EMPTY mbid string as absent — some
    /// Last.fm/Spotify music results send `mbid: ""`, and `mbid ?? name` would then route to an
    /// empty id (→ `getArtist("")` → the artist error screen). Falls back to the name, which the
    /// backend resolves against library artists by name.
    var routeId: String {
        if let m = mbid, !m.isEmpty { return m }
        return name
    }

    enum CodingKeys: String, CodingKey {
        case type
        case externalId = "id"
        case name, mbid, image, listeners
    }

    /// Custom decode because `id` is polymorphic: a number for iTunes podcasts, "deezer:<id>" for Deezer, absent for
    /// Last.fm. Synthesized decoding would throw on a numeric id and blank the whole results array, so a numeric
    /// id is coerced to String and a missing name/type is tolerated.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(ResultType.self, forKey: .type)) ?? .unknown
        if let intId = try? c.decode(Int.self, forKey: .externalId) {
            externalId = String(intId)
        } else {
            externalId = try? c.decode(String.self, forKey: .externalId)
        }
        name      = (try? c.decode(String.self, forKey: .name)) ?? ""
        mbid      = try? c.decode(String.self, forKey: .mbid)
        image     = try? c.decode(String.self, forKey: .image)
        listeners = try? c.decode(Int.self, forKey: .listeners)
    }
}

/// Last.fm alias correction returned when the server resolves a misspelled or alternate
/// artist name. E.g. query "radiohead" → canonical "Radiohead" with mbid.
struct AliasInfo: Decodable, Sendable {
    let original:  String
    let canonical: String
    let mbid:      String?
}

/// Response envelope for GET /search/discover?type=all.
struct DiscoverAllResponse: Decodable, Sendable {
    let results:   [DiscoverResult]
    let aliasInfo: AliasInfo?
}

// MARK: - Unified library search models

/// Podcast from GET /api/search/ (library search). Distinct from the shared `Podcast`: it uses `imageUrl` (not
/// `coverUrl`), has no `episodes` array, and lacks subscription and feed fields.
struct SearchPodcast: Identifiable, Decodable, Sendable {
    let id:           String
    let title:        String
    let author:       String?
    let description:  String?
    /// Cover art URL key used by the search service (field name is `imageUrl`).
    let imageUrl:     String?
    /// Optional to match the shared `Podcast` model + DB schema (the `episodeCount`
    /// column is nullable). A required `Int` here would fail the whole `podcasts` array
    /// decode on any null — silently emptying library search (same class as the
    /// polymorphic-id crash fixed in `DiscoverResult`).
    let episodeCount: Int?
}

/// Audiobook shape returned by GET /api/search/ (library search).
///
/// `series` is a plain `String?` (not a nested struct), and `duration` is nullable.
struct SearchAudiobook: Identifiable, Decodable, Sendable {
    let id:          String
    let title:       String
    let author:      String?
    let narrator:    String?
    /// Series name only (e.g. "The Stormlight Archive").
    let series:      String?
    let description: String?
    let coverUrl:    String?
    let duration:    Double?
}

/// Podcast episode from GET /api/search/?type=all (library search).
/// `publishedAt`, `duration` and `audioUrl` are optional: a required field that arrives null would throw and
/// silently empty the whole episodes array. Field names match the JSON keys, so no `CodingKeys` is needed.
struct SearchEpisode: Identifiable, Decodable, Sendable {
    let id:           String
    let title:        String
    let description:  String?
    let podcastId:    String
    let podcastTitle: String
    let publishedAt:  String?   // ISO 8601 string; optional for decode safety
    let duration:     Double?   // seconds; optional for decode safety
    let audioUrl:     String?
}

/// Search result envelope for GET /api/search/?type=all. `podcasts` and `audiobooks` use their own search-result
/// structs because the backend's search output differs from the full library shapes; `artists`, `albums` and
/// `tracks` reuse the shared library models.
struct SearchResults: Decodable, Sendable {
    let artists:    [Artist]
    let albums:     [Album]
    let tracks:     [Track]
    let podcasts:   [SearchPodcast]
    let audiobooks: [SearchAudiobook]
    /// Podcast episode matches. Rendered as a "Podcast Episodes" section in search results;
    /// tapping an episode navigates to the parent podcast via `episode.podcastId`.
    /// Included in `SearchViewModel.hasAnyResults` so episodes count toward non-empty state.
    let episodes:   [SearchEpisode]
}

// MARK: - Podcast discovery model (for PodcastAddView)

/// Rich podcast result from GET /search/discover?type=podcasts (feedUrl, genres, trackCount). The global
/// search tab uses `DiscoverResult` instead.
/// The backend's `id` is polymorphic: an iTunes collectionId (JSON number) or a Deezer "deezer:<id>" string.
/// Both decode to a Swift `String`.
struct DiscoverPodcastResult: Identifiable, Codable, Sendable {
    let id:         String
    let name:       String
    let artist:     String
    let coverUrl:   String?
    let feedUrl:    String?
    let genres:     [String]
    let trackCount: Int

    private enum CodingKeys: String, CodingKey {
        case id, name, artist, coverUrl, feedUrl, genres, trackCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        name       = try  c.decode(String.self,   forKey: .name)
        artist     = try  c.decode(String.self,   forKey: .artist)
        coverUrl   = try? c.decode(String.self,   forKey: .coverUrl)
        feedUrl    = try? c.decode(String.self,   forKey: .feedUrl)
        genres     = (try? c.decode([String].self, forKey: .genres)) ?? []
        trackCount = (try? c.decode(Int.self,      forKey: .trackCount)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,         forKey: .id)
        try c.encode(name,       forKey: .name)
        try c.encode(artist,     forKey: .artist)
        try c.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try c.encodeIfPresent(feedUrl,  forKey: .feedUrl)
        try c.encode(genres,     forKey: .genres)
        try c.encode(trackCount, forKey: .trackCount)
    }

    /// iTunes podcast id string (nil for Deezer-sourced results prefixed "deezer:").
    var itunesIdString: String? { id.hasPrefix("deezer:") ? nil : id }
    /// True when a feedUrl is available — required for `subscribePodcast`.
    var canSubscribe: Bool { feedUrl != nil }
}
