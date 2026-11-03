import Foundation
import Observation
import os

// MARK: - Card playback
//
// The library grid's "play from a card" path, split out of CollectionViewModel (431 lines, six
// jobs in one file). This is the split, not a rewrite: same code, same names, same call sites.
// `startingIds` stays a stored property on the class — Swift does not allow stored properties
// in extensions — and the grids read it to spin the right badges.

/// One line per card play, so a tap that plays nothing can be told apart from a tap that played
/// the wrong music. `api-timing` proves a request ran; it cannot say why a tap produced none.
private let cardPlayLog = Logger(subsystem: "com.chevron7locked.kima", category: "card-play")

extension CollectionViewModel {

    /// Play from the library grid: this artist's own music, newest owned album first, disc then
    /// track inside it.
    ///
    /// Not the "popular" list: global popularity carries rows for tracks the user does not own,
    /// which have no stream to play. Not radio either: radio is seeded from the similarity
    /// graph, so tapping one artist can queue another artist's music.
    ///
    /// The queue comes from `getArtistPlayTracks`: one small request, ordered by the server. The
    /// artist page carries the same tracks inside a payload measured at 1,012,720 bytes for an
    /// artist with 101 albums, which takes seconds to fetch.
    func playArtist(id: String, using client: KimaAPIClient, player: PlaybackController, toast: ToastCenter) async {
        guard !startingIds.contains(id) else {
            cardPlayLog.debug("artist \(id, privacy: .public) already starting — tap ignored")
            return
        }
        startingIds.insert(id)
        defer { startingIds.remove(id) }
        cardPlayLog.notice("artist \(id, privacy: .public) play tapped")
        #if DEBUG
        await DebugCardPlayDelay.apply()
        #endif
        do {
            let queue = try await client.getArtistPlayTracks(id: id)
            guard !queue.tracks.isEmpty else {
                cardPlayLog.notice("artist \(id, privacy: .public) queue came back empty")
                toast.show("\(queue.artist.name.lowercased()) has no playable tracks", style: .error)
                return
            }
            player.play(tracks: queue.tracks, startAt: 0)
            cardPlayLog.notice("artist \(id, privacy: .public) queued \(queue.tracks.count) tracks")
        } catch {
            cardPlayLog.error("artist \(id, privacy: .public) play failed: \(String(reflecting: error), privacy: .public)")
            toast.show("couldn't play \(artistName(for: id) ?? "that artist")", style: .error)
        }
    }

    func playAlbum(id: String, using client: KimaAPIClient, player: PlaybackController, toast: ToastCenter) async {
        guard !startingIds.contains(id) else { return }
        startingIds.insert(id)
        defer { startingIds.remove(id) }
        #if DEBUG
        await DebugCardPlayDelay.apply()
        #endif
        do {
            let album = try await client.getAlbum(id: id)
            let tracks = album.tracksInOrder
            guard !tracks.isEmpty else {
                toast.show("this album has no playable tracks", style: .error)
                return
            }
            player.play(tracks: tracks, startAt: 0)
        } catch {
            toast.show("couldn't play \(albumTitle(for: id) ?? "that album")", style: .error)
        }
    }

    /// Names for the failure copy, read from the loaded page (no extra request at failure time).
    private func artistName(for id: String) -> String? {
        guard case .loaded(let artists) = artistsPhase else { return nil }
        return artists.first(where: { $0.id == id })?.effectiveName.lowercased()
    }

    private func albumTitle(for id: String) -> String? {
        guard case .loaded(let albums) = albumsPhase else { return nil }
        return albums.first(where: { $0.id == id })?.effectiveTitle.lowercased()
    }
}
