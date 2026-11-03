import Foundation

// MARK: - Collection domain types
//
// Split out of LibraryViewModel.swift, which had six jobs in one file (431 lines). Pure move:
// same declarations, same names, same comments, no behaviour change.

// Generic loading state shared with AlbumDetailViewModel / ArtistDetailViewModel.
// Defined here so callers need no additional imports.
enum LoadPhase<T: Sendable>: Sendable {
    case loading
    case failed(String)
    case loaded(T)

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
}

/// Filter applied to Artists and Albums tabs. Tracks tab is always "owned".
/// Raw values are the server query-param strings.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case owned     = "owned"
    case discovery = "discovery"
    case all       = "all"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .owned:     return "in your library"
        case .discovery: return "recommended"
        case .all:       return "all"
        }
    }
    var description: String {
        switch self {
        case .owned:     return "music you own or have saved"
        case .discovery: return "artists suggested by your listening history"
        case .all:       return "everything, owned and recommended"
        }
    }
}

/// Sort options mirroring web's `SortOption` type.
/// "recent" available only on Albums; "tracks" available only on Artists.
enum LibrarySortOption: String, CaseIterable, Identifiable {
    case name     = "name"
    case nameDesc = "name-desc"
    case recent   = "recent"
    case tracks   = "tracks"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .name:     return "name a–z"
        case .nameDesc: return "name z–a"
        case .recent:   return "year (newest)"
        case .tracks:   return "most tracks"
        }
    }
    func available(for tab: CollectionTab) -> Bool {
        switch self {
        case .name, .nameDesc: return true
        case .recent:          return tab == .albums
        case .tracks:          return tab == .artists
        }
    }
}

/// Active Collection tab.
enum CollectionTab: String, CaseIterable, Identifiable {
    case artists, albums, tracks
    var id: String { rawValue }
    var label: String { rawValue.lowercased() }
}
