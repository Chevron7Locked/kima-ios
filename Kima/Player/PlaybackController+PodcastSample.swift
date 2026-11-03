import Foundation

// MARK: - First-episode sample of a show not followed yet

extension PlaybackController {

    /// Plays a not-followed show's first episode in the main player (lock screen, scrubbing) from the server's
    /// sample stream. Unlike a followed episode it saves no position, is never marked finished, and stops at its end.
    /// The episode's podcast id is the Apple id, so "go to show" opens the preview page.
    func playPodcastSample(_ snippet: PodcastSnippet, of preview: PodcastPreview, itunesId: String, client: KimaAPIClient) {
        cancelSkipDebounce()
        stopLongForm()

        let episode = Episode(
            id: "sample-\(itunesId)", title: snippet.title, description: nil, duration: snippet.duration,
            publishedAt: snippet.publishedAt, episodeNumber: nil, season: nil, progress: nil,
            imageUrl: nil, isDownloaded: nil, audioUrl: nil
        )
        queue = []
        playbackType = .podcastEpisode(podcastId: itunesId, episode: episode, queue: [episode])
        podcastSampleItunesId = itunesId
        longFormAPIClient = client
        longFormNowPlayingMeta = LongFormNowPlayingMeta(
            title: snippet.title, artist: preview.title, coverURL: longFormCoverURL(preview.coverUrl)
        )
        lastSavedProgressTime = 0

        engine.claimAudioSession(mode: .spokenAudio)
        loadPodcastEpisode(podcastId: itunesId, episode: episode, seekTo: 0, autoplay: true)
        nowPlayingHook?()
    }

    /// True while the sample of this show is the item in the player.
    func isPlayingSample(of itunesId: String) -> Bool {
        podcastSampleItunesId == itunesId
    }
}
