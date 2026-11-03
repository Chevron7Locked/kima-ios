import Foundation

// MARK: - Continue listening → play

extension PlaybackController {
    /// Plays a continue-listening item: an audiobook from its saved place, a podcast's episode in
    /// progress (else its newest unplayed), an album in disc and track order, an artist's top songs.
    /// False when it could not load or had nothing to play.
    func playRecent(_ item: RecentlyListenedItem, client: KimaAPIClient) async -> Bool {
        // Same signal as a mix tap: the bar comes back for whatever the user just asked to play.
        notePlayRequest()
        do {
            switch item.type?.lowercased() {
            case "audiobook":
                let book = try await client.getAudiobook(id: item.id)
                await playAudiobook(book, client: client)
            case "podcast":
                let podcast = try await client.getPodcast(id: item.id)
                guard let episode = Self.resumeEpisode(in: podcast.episodes) else { return false }
                playPodcastEpisode(episode, podcast: podcast, queue: podcast.episodes, client: client)
            case "album":
                let tracks = try await client.getAlbum(id: item.id).tracksInOrder
                guard !tracks.isEmpty else { return false }
                play(tracks: tracks, startAt: 0)
            default:
                guard let tracks = try await client.getArtist(id: item.id).topTracks, !tracks.isEmpty else { return false }
                play(tracks: tracks, startAt: 0)
            }
            return true
        } catch {
            return false
        }
    }

    /// The episode to resume: one started and not finished, else the newest not finished, else the newest.
    static func resumeEpisode(in episodes: [Episode]) -> Episode? {
        episodes.first { ($0.progress?.currentTime ?? 0) > 0 && $0.progress?.isFinished != true }
            ?? episodes.first { $0.progress?.isFinished != true }
            ?? episodes.first
    }
}
