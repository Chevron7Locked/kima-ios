import SwiftUI

// Title, artist and play-count taps leave the full player for the matching page.

extension FullPlayerView {

    // MARK: - Title / artist navigation

    /// Title tap → the album detail. Music only: long-form (audiobook/podcast) has no album
    /// page, so we simply close the player. Mirrors the notification deep-link in
    /// `NavigationRouter.open` — publish the tab + route, let the Library tab consume it.
    func openAlbum() {
        dismiss()
        guard !player.playbackType.isLongForm,
              let albumId = player.currentTrack?.album?.id else { return }
        env.router.selectedTab = .library                   // hosts album/artist
        env.router.pendingLibraryRoute = .album(id: albumId)
    }

    func openStats() {
        dismiss()
        env.router.selectedTab = .more
        env.router.statsRequest = true
    }

    /// Artist tap → the artist detail. Music only (long-form has no artist page → just dismiss).
    func openArtist() {
        dismiss()
        guard !player.playbackType.isLongForm,
              let artistId = player.currentTrack?.artist?.id else { return }
        env.router.selectedTab = .library
        env.router.pendingLibraryRoute = .artist(id: artistId)
    }
}
