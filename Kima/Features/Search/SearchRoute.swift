import Foundation

/// Navigation destinations pushed from `SearchView`'s `NavigationStack`.
/// Covers library music, podcasts, and audiobooks.
/// Discover-only artists (no library id) are display-only in search results
/// and do not produce a route.
enum SearchRoute: Hashable {
    case album(id: String)
    case artist(id: String)
    /// Library-subscribed podcast id.
    case podcast(id: String)
    case audiobook(id: String)
}
