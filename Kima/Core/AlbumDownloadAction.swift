import Foundation

/// Queues a Lidarr download for an album that is not on the server yet; shared by the album and artist screens.
@MainActor
enum AlbumDownloadAction {
    static func run(album: Album, artistName: String, client: KimaAPIClient, toast: ToastCenter) async {
        guard let mbid = album.rgMbid ?? album.mbid else {
            toast.show("can't download: this album has no MusicBrainz ID", style: .error)
            return
        }
        let title = album.effectiveTitle
        do {
            let response = try await client.downloadAlbum(
                artistName: artistName,
                albumTitle: title,
                rgMbid: mbid
            )
            if response.duplicate == true {
                toast.show("\(title) is already downloading", style: .info)
            } else {
                toast.show("added to download queue", style: .success)
            }
        } catch {
            toast.show(AcquirePermission.failureMessage(error, fallback: "couldn't start the download. try again."),
                       style: .error)
        }
    }
}
