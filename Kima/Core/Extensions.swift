import Foundation

// MARK: - EmptyRequestBody
//
// Single placeholder body for POST/PUT endpoints that accept no payload.

struct EmptyRequestBody: Encodable, Sendable {}

// MARK: - FailableDecodable
//
// Lenient array-element wrapper: a malformed element decodes to nil instead of throwing, and the container still
// advances. Usage: `((try? c.decode([FailableDecodable<T>].self, forKey: k)) ?? []).compactMap(\.value)`.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

// MARK: - String.strippingHTML
//
// Shared HTML-stripping helper for PodcastDetailView and AudiobookDetailViewModel.

extension String {
    /// Strips HTML tags and decodes common entities. Synchronous; safe on any thread.
    var strippingHTML: String {
        let stripped = replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Int.abbreviatedCount
//
// Compact human-readable label for large integers.

extension Int {
    /// Returns a compact string: "1.2M", "340K", or the raw number for values below 1 000.
    var abbreviatedCount: String {
        if self >= 1_000_000 { return String(format: "%.1fM", Double(self) / 1_000_000) }
        if self >= 1_000     { return String(format: "%.0fK", Double(self) / 1_000) }
        return "\(self)"
    }
}

// MARK: - Array.chunked
//
// Splits an array into ordered slices of at most `size` elements. PlaylistPickerSheet uses it to stay under the
// 500-item cap on POST /playlists/:id/items/batch.

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - PlaylistItem.asTrack
//
// Converts a playlist item into the `Track` type PlaybackController plays.

extension PlaylistItem {
    var asTrack: Track {
        Track(
            id: track.id,
            title: track.title,
            duration: track.duration,
            artist: TrackArtistRef(
                id: track.album?.artist?.id,
                name: track.album?.artist?.name
            ),
            album: TrackAlbumRef(
                id: track.album?.id,
                title: track.album?.title,
                coverArt: track.album?.coverArt
            )
        )
    }
}
