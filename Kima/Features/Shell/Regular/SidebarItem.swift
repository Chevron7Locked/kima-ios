import SwiftUI

// MARK: - SidebarItem

/// Destinations in the iPad 2-column shell's left sidebar. All but `.settings` are the nav rows in
/// `KimaSidebar`, in `indexed` order; `.settings` is pinned at the bottom beside the Activity bell.
enum SidebarItem: Int, CaseIterable, Identifiable, Hashable {
    case home, library, playlists, discover, radio, vibeMap, audiobooks, podcasts, stats, search
    case settings

    var id: Int { rawValue }

    /// The nav rows, in display order. Settings is intentionally excluded —
    /// it's a pinned footer row.
    static let indexed: [SidebarItem] = [
        .home, .library, .playlists, .discover, .radio, .vibeMap, .audiobooks, .podcasts, .stats, .search,
    ]

    var title: String {
        switch self {
        case .home:       return "home"
        case .library:    return "library"
        case .playlists:  return "playlists"
        case .discover:   return "discover"
        case .radio:      return "radio"
        case .vibeMap:    return "vibe map"
        case .audiobooks: return "audiobooks"
        case .podcasts:   return "podcasts"
        case .stats:      return "stats"
        case .search:     return "search"
        case .settings:   return "settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home:       return "house.fill"
        case .library:    return "music.note.list"
        case .playlists:  return "rectangle.stack"
        case .discover:   return "safari"
        case .radio:      return "dot.radiowaves.left.and.right"
        case .vibeMap:    return "point.3.connected.trianglepath.dotted"
        case .audiobooks: return "headphones"
        case .podcasts:   return "mic"
        case .stats:      return "chart.bar.xaxis"
        case .search:     return "magnifyingglass"
        case .settings:   return "gearshape.fill"
        }
    }
}

#if DEBUG
extension SidebarItem {
    /// The section a `-kima-open <type>` launch arg lands on in the sidebar layout (the iPhone reaches these
    /// through More), else nil.
    static func debugLanding(for requested: String?) -> SidebarItem? {
        switch requested {
        case "vibe":                  return .vibeMap
        case "settings":              return .settings
        case "search":                return .search
        case "stats":                 return .stats
        case "playlist", "playlists": return .playlists
        case "discover":              return .discover
        case "radio":                 return .radio
        default:                      return nil
        }
    }
}
#endif
