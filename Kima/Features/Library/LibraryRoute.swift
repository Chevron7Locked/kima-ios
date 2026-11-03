import SwiftUI

/// Navigation destinations inside the Home, Library and More tabs' NavigationStacks.
/// Drives `NavigationStack(path:)`; add a case here and give it a screen in
/// `LibraryRouteDestination`, which every tab's stack shares.
enum LibraryRoute: Hashable {
    case album(id: String)
    case artist(id: String)
    /// User playlists list (PlaylistsListView).
    case playlists
    /// Single user-playlist detail (PlaylistDetailView).
    case playlistDetail(id: String)
    /// Single browse/Deezer playlist detail (BrowsePlaylistDetailView).
    case browsePlaylistDetail(id: String)
    #if DEBUG
    /// Deep-link-only settings screens (no user path reaches these from tabs).
    case designlab
    case licenses
    case changelog
    #endif
}

/// The screen each library route opens, shared by every tab's NavigationStack.
struct LibraryRouteDestination: View {
    let route: LibraryRoute
    @Binding var path: [LibraryRoute]

    var body: some View {
        switch route {
        case .album(let id):
            AlbumDetailView(albumId: id, path: $path)
        case .artist(let id):
            ArtistDetailView(artistId: id, path: $path)
        case .playlists:
            PlaylistsListView(path: $path)
        case .playlistDetail(let id):
            PlaylistDetailView(playlistId: id, path: $path)
        case .browsePlaylistDetail(let id):
            BrowsePlaylistDetailView(playlistId: id)
        #if DEBUG
        case .designlab:
            DesignLabView()
        case .licenses:
            LicensesView()
        case .changelog:
            ChangelogView()
        #endif
        }
    }
}

extension View {
    func libraryRouteDestinations(path: Binding<[LibraryRoute]>) -> some View {
        navigationDestination(for: LibraryRoute.self) { LibraryRouteDestination(route: $0, path: path) }
    }
}
