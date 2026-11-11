import Foundation
@testable import Kima

extension Track {
    /// A minimal 100-second track whose title is its id.
    static func fixture(_ id: String) throws -> Track {
        try JSONDecoder().decode(Track.self, from: Data(#"{"id":"\#(id)","title":"\#(id)","duration":100}"#.utf8))
    }

    /// The same track filed under an album whose title is its id (membership tests).
    static func fixture(_ id: String, albumId: String) throws -> Track {
        try JSONDecoder().decode(Track.self, from: Data(
            #"{"id":"\#(id)","title":"\#(id)","duration":100,"album":{"id":"\#(albumId)","title":"\#(albumId)"}}"#.utf8))
    }

    /// The same track credited to an artist ref (artist-membership tests). Built in code, so
    /// id-less and name-only refs — the cases the artist page's fallback exists for — are easy.
    static func fixture(_ id: String, artist: TrackArtistRef) -> Track {
        Track(id: id, title: id, duration: 100, artist: artist)
    }
}

extension TrackArtistRef {
    /// A credited artist stub with both fields settable (nil = the server omitted it).
    static func ref(id: String?, name: String?) -> TrackArtistRef {
        TrackArtistRef(id: id, name: name)
    }
}

extension Episode {
    /// A minimal 30-minute episode whose title is its id.
    static func fixture(_ id: String) throws -> Episode {
        try JSONDecoder().decode(Episode.self, from: Data(
            #"{"id":"\#(id)","title":"\#(id)","duration":1800,"publishedAt":"2026-01-01T00:00:00Z"}"#.utf8))
    }
}
