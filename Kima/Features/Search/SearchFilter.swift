import Foundation

// MARK: - Filter tab enum

/// Scope selector shown as pill chips below the search bar.
/// all: library and discover results together. library: local sections only. discover: external sections only.
/// soulseek: direct P2P search, offered only when the server has Soulseek credentials
/// (`SearchViewModel.soulseekEnabled`).
enum SearchFilter: String, CaseIterable, Identifiable {
    case all, library, discover, soulseek

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:      "all"
        case .library:  "library"
        case .discover: "discover"
        case .soulseek: "Soulseek"
        }
    }

    /// SF Symbol for the idle-state entry row (see `SearchIdlePrompt`).
    var icon: String {
        switch self {
        case .all:      "square.stack.3d.up"
        case .library:  "books.vertical"
        case .discover: "safari"
        case .soulseek: "antenna.radiowaves.left.and.right"
        }
    }

    /// One-line teaching copy for the idle-state entry row — explains the scope
    /// before the user has typed anything.
    var idleDescription: String {
        switch self {
        case .all:      "your library and new music"
        case .library:  "only what's in your library"
        case .discover: "music that isn't in your library yet"
        case .soulseek: "search Soulseek for files to download"
        }
    }
}
