import Foundation

// Codable models for the Home page sections that live outside the core library domain.

// MARK: - HomeMix

/// A programmatic mix from GET /api/mixes (bare [HomeMix] array response).
/// `coverUrls` contains relative cover-art identifier paths (same format as Artist.image /
/// Album.coverArt) — pass individual entries to `CoverArtImage(coverId:)`.
/// The first four render as a 2×2 mosaic in MixCard.
struct HomeMix: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String
    let coverUrls: [String]
    let trackCount: Int
}

// MARK: - HomePopularArtist

/// A popular artist from GET /api/discover/popular-artists (Last.FM sourced).
/// `id` is nil for Last.FM entries that haven't been matched to a library artist.
/// `image` is a relative cover-art identifier — pass to `CoverArtImage(coverId:)`.
struct HomePopularArtist: Codable, Sendable {
    let id: String?
    let name: String
    let image: String?
    let listeners: Int?

    /// Stable ForEach diffing key — falls back to name when id is nil.
    var stableId: String { id ?? name }
}

// MARK: - HomePlaylistPreview

/// A Deezer-sourced playlist preview from GET /api/browse/all.
/// `imageUrl` is an absolute external CDN URL — use `AsyncImage(url:)` directly,
/// NOT `CoverArtImage` (which expects a relative server-side identifier).
struct HomePlaylistPreview: Codable, Sendable, Identifiable {
    let id: String
    let source: String
    let type: String
    let title: String
    let description: String?
    let creator: String?
    let imageUrl: String?
    let trackCount: Int
    let url: String
}

// MARK: - BrowsePlaylistDetail

/// A full Deezer playlist from GET /api/browse/playlists/:id.
/// Returned by the browse (not user-playlist) endpoint; IDs are Deezer numeric IDs.
struct BrowsePlaylistDetail: Decodable, Sendable {
    let id: String
    let title: String
    let description: String?
    let creator: String?
    let imageUrl: String?
    let trackCount: Int
    let tracks: [BrowsePlaylistTrack]
    let isPublic: Bool?
    let source: String?
    let url: String?
}

/// A single track inside a `BrowsePlaylistDetail`.
struct BrowsePlaylistTrack: Decodable, Sendable, Identifiable {
    let deezerId: String
    let title: String
    let artist: String
    let artistId: String?
    let album: String?
    let albumId: String?
    let durationMs: Int?
    let previewUrl: String?
    let coverUrl: String?

    var id: String { deezerId }

    /// Duration formatted as "M:SS" ("H:MM:SS" from an hour).
    var durationFormatted: String {
        guard let ms = durationMs, ms > 0 else { return "" }
        return Double(ms / 1000).durationFormatted
    }
}

// MARK: - MixTrack (decode-only)

/// Decode-only track shape inside mix payloads (GET /api/mixes/:id and /api/mixes/mood/buckets/:mood).
/// Those endpoints return raw rows whose album carries the cover as `coverUrl`, not `coverArt` as the rest of
/// the API does. Mapping it here keeps the shared `Track`/`TrackAlbumRef` decoding intact.
/// Convert with `asTrack()` for playback.
struct MixTrack: Decodable, Sendable {
    let id: String
    let title: String
    let duration: Double?
    let album: MixTrackAlbum?

    struct MixTrackAlbum: Decodable, Sendable {
        let id: String?
        let title: String?
        let coverUrl: String?
        let artist: MixTrackArtist?
    }

    struct MixTrackArtist: Decodable, Sendable {
        let id: String?
        let name: String?
    }

    /// Build the app `Track`, mapping the album's `coverUrl` onto `TrackAlbumRef.coverArt`
    /// so CoverArtImage and Now Playing artwork resolve. Artist comes from `album.artist`
    /// (mirrors the web's `t.album?.artist` mapping).
    func asTrack() -> Track {
        Track(
            id: id,
            title: title,
            duration: duration ?? 0,
            artist: album?.artist.map { TrackArtistRef(id: $0.id, name: $0.name) },
            album: album.map { TrackAlbumRef(id: $0.id, title: $0.title, coverArt: $0.coverUrl) }
        )
    }
}

// MARK: - API response envelopes

/// POST /api/mixes/refresh → { message, mixes: [...] }
struct MixesRefreshResponse: Codable, Sendable {
    let message: String
    let mixes: [HomeMix]
}

/// GET /api/mixes/:id → { ...mix, tracks: [...] }. Only `tracks` is needed for playback;
/// the spread mix metadata keys are ignored.
struct MixDetailResponse: Decodable, Sendable {
    let tracks: [MixTrack]?
}

/// GET /api/recommendations/for-you → { artists: [...] }
/// Uses the same Artist shape as /library/artists.
struct RecommendationsForYouResponse: Codable, Sendable {
    let artists: [Artist]
}

/// GET /api/discover/popular-artists → { artists: [...] }
struct PopularArtistsAPIResponse: Codable, Sendable {
    let artists: [HomePopularArtist]
}

/// GET /api/browse/all → { playlists: [...], radios: [...], genres: [...] }
/// Only `playlists` is decoded; other keys are ignored without error.
struct BrowseAllAPIResponse: Codable, Sendable {
    let playlists: [HomePlaylistPreview]
}

// MARK: - RecentlyListenedItem

/// Lenient recently-listened item. The server mixes artists, podcasts, audiobooks and albums in
/// `{ items: [...] }`, so only `id` is required and every other field is optional.
/// Shape unverified against a live server; an item that fails to decode is skipped at the call site.
struct RecentlyListenedItem: Codable, Sendable, Identifiable {
    let id: String
    /// Entity name (artist/podcast/audiobook) or track title.
    let name: String?
    let title: String?
    /// Cover-art identifiers — check both fields since entity types differ.
    let coverArt: String?
    let image: String?
    /// Type discriminator, if the server sends one ("artist", "album", "podcast", "audiobook").
    let type: String?
    /// Embedded artist name when the item is a track.
    let artistName: String?
    /// Author field for podcasts and audiobooks (may be nil for artist-type items).
    let author: String?
    /// Playback progress as a percentage 0–100 (only meaningful for podcasts/audiobooks).
    let progress: Double?
    /// For a podcast: the episode in progress (`id` is the show's).
    var episodeId: String? = nil

    var displayTitle: String { name ?? title ?? id }
    var coverId: String? { coverArt ?? image }

    /// "Podcast"/"Audiobook"/"Album"/"Artist", or the podcast/audiobook author when present —
    /// the Home rail subtitle line. Shared by every card presenting this item (`ContinueCard`,
    /// `ContinueSpotlightCard`) so the mixed-type logic lives in one place.
    var homeSubtitle: String {
        switch type?.lowercased() {
        case "podcast":
            let a = author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (a.isEmpty || a.lowercased() == displayTitle.lowercased()) ? "podcast" : a
        case "audiobook":
            let a = author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return a.isEmpty ? "audiobook" : a
        case "album": return "album"
        default:       return "artist"
        }
    }

    /// What the item is, in one lowercase word: "artist", "album", "podcast" or "audiobook".
    var typeLabel: String {
        let t = type?.lowercased() ?? ""
        return ["podcast", "audiobook", "album"].contains(t) ? t : "artist"
    }

    /// SF Symbol for the no-cover tile: a mic for podcasts, a book for audiobooks.
    var placeholderSymbol: String {
        switch type?.lowercased() {
        case "podcast":   return "mic"
        case "audiobook": return "book"
        default:          return "music.note"
        }
    }

    /// Subtitle for the full-width spotlight card, which renders text at hero scale: only meaningful content
    /// (an author name) earns the line. homeSubtitle's bare type label ("artist") looks like broken data at that
    /// size, so ContinueCard keeps homeSubtitle.
    var spotlightSubtitle: String? {
        let t = type?.lowercased()
        guard t == "podcast" || t == "audiobook" else { return nil }
        let a = author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !a.isEmpty, a.lowercased() != displayTitle.lowercased() else { return nil }
        return a.lowercased()
    }

    /// True for an in-progress podcast/audiobook — the only case with a progress bar
    /// (artists/albums don't carry a `progress` value).
    var hasPlaybackProgress: Bool {
        let t = type?.lowercased() ?? ""
        return (t == "podcast" || t == "audiobook") && (progress ?? 0) > 0
    }
}
