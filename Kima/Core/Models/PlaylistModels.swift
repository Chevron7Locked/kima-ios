import Foundation

// Codable shapes for the Playlists feature.

// MARK: - Shared

struct PlaylistUser: Codable, Sendable {
    let username: String
}

// MARK: - Summary (GET /playlists → [PlaylistSummary])

/// First-4-items from the list endpoint, used to build the cover mosaic.
struct PlaylistSummaryItem: Codable, Sendable, Identifiable {
    let id: String
    let track: PlaylistSummaryTrack
}

struct PlaylistSummaryTrack: Codable, Sendable {
    let album: PlaylistSummaryAlbum?
}

struct PlaylistSummaryAlbum: Codable, Sendable {
    let coverUrl: String?
}

/// One row from GET /playlists. The server computes `trackCount`, `isOwner`, and `isHidden`
/// server-side and inlines them. `items` contains the first 4 items for the mosaic.
struct PlaylistSummary: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let isPublic: Bool?
    let isOwner: Bool?
    let isHidden: Bool?
    let user: PlaylistUser?
    let trackCount: Int?
    /// First 4 items — server sends them for mosaic art. May be absent on older servers.
    let items: [PlaylistSummaryItem]?
}

// MARK: - Playlist Item (GET /playlists/:id → PlaylistDetail.items)

struct PlaylistItemArtist: Codable, Sendable {
    let id: String?
    let name: String
}

/// Album ref embedded in a playlist track item. The server aliases `coverUrl` → `coverArt`
/// when formatting items.
struct PlaylistItemAlbum: Codable, Sendable {
    let id: String?
    let title: String?
    let coverArt: String?
    let artist: PlaylistItemArtist?
}

struct PlaylistItemTrack: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let duration: Double
    let album: PlaylistItemAlbum?
}

struct PlaylistItem: Codable, Sendable, Identifiable {
    let id: String
    let sort: Int?
    let track: PlaylistItemTrack
}

// MARK: - Playlist Detail (GET /playlists/:id)

struct PlaylistDetail: Codable, Sendable, Identifiable {
    let id: String
    var name: String
    var isPublic: Bool?
    let isOwner: Bool?
    var isHidden: Bool?
    let user: PlaylistUser?
    var trackCount: Int?
    let pendingCount: Int?
    /// In display order: the server sends them already reversed when `reverseOrder` is on.
    var items: [PlaylistItem]?
    /// The owner flipped the playlist to show newest additions first.
    var reverseOrder: Bool?
}

// MARK: - Create / Update responses

/// Minimal shape returned by POST /playlists and PUT /playlists/:id.
struct PlaylistMutationResponse: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let isPublic: Bool?
}

// MARK: - Request bodies

struct CreatePlaylistBody: Encodable, Sendable {
    let name: String
    let isPublic: Bool
}

struct UpdatePlaylistBody: Encodable, Sendable {
    var name: String? = nil
    var isPublic: Bool? = nil
    var reverseOrder: Bool? = nil
}

/// POST /playlists/:id/items/batch body. 1..500 track ids; order is preserved server-side.
struct BatchAddTracksBody: Encodable, Sendable {
    let trackIds: [String]
}

/// POST /playlists/:id/items/batch response — summary counts plus the created items.
struct BatchAddTracksResponse: Decodable, Sendable {
    let added: Int
    let skippedExisting: Int
    let skippedInvalid: Int
    let items: [PlaylistItem]
}
