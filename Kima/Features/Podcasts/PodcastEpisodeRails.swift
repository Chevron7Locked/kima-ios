import SwiftUI

// MARK: - PodcastEpisodeRails

/// The top of the podcasts page, from the server's listening list: "continue listening" (episodes partway through,
/// with what is left) and "new episodes" (each followed show's newest one while unplayed). A card opens its show;
/// its play badge plays the episode, or pauses it when it is the one playing. Each rail hides when empty.
struct PodcastEpisodeRails: View {
    let continueItems: [PodcastListeningRow]
    let newItems: [PodcastListeningRow]
    /// The full show for a row, so the player names it and "go to show" opens it.
    let podcast: (PodcastListeningShow) -> Podcast
    let onOpenShow: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player

    private static let cardWidth: CGFloat = 132

    var body: some View {
        if !continueItems.isEmpty {
            KimaSectionHeader(title: "continue listening")
            rail(continueItems) { item in
                let left = max(0, item.episode.duration - (item.episode.progress?.currentTime ?? 0))
                return "\(left.lengthLabel) left"
            }
        }
        if !newItems.isEmpty {
            KimaSectionHeader(title: "new episodes")
            rail(newItems) { $0.episode.publishedAt.podcastDateDisplay }
        }
    }

    private func rail(_ items: [PodcastListeningRow], detail: @escaping (PodcastListeningRow) -> String) -> some View {
        KimaRail(tileWidth: Self.cardWidth) { width in
            ForEach(items) { item in
                KimaCoverCard(
                    title: item.episode.title,
                    // What is left or when it came out goes first: a long show name truncates after it.
                    subtitle: "\(detail(item)) · \(item.podcast.title)",
                    titleLines: 2,
                    isPlaying: isPlaying(item.episode),
                    onPlay: { play(item) },
                    onTap: { onOpenShow(item.podcast.id) }
                ) {
                    CoverArtImage(coverId: item.episode.coverUrl ?? item.podcast.coverUrl, size: 256, cornerRadius: 0,
                                  placeholderSymbol: "mic")
                        .overlay(alignment: .bottom) { progressBar(item.episode) }
                }
                .frame(width: width)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.episode.title), \(item.podcast.title), \(detail(item))")
            }
        }
    }

    /// Flush with the cover's bottom edge, under the play badge; only for an episode partway through.
    @ViewBuilder
    private func progressBar(_ episode: PodcastListeningEpisode) -> some View {
        if let p = episode.progress, p.currentTime > 0, !p.isFinished {
            KimaProgressBar(fraction: p.progress / 100, track: Color.black.opacity(0.45))
        }
    }

    private func isPlaying(_ episode: PodcastListeningEpisode) -> Bool {
        guard player.isPlaying, case .podcastEpisode(_, let current, _) = player.playbackType else { return false }
        return current.id == episode.id
    }

    /// The episode on its own: what plays after it comes from the server when it ends.
    private func play(_ item: PodcastListeningRow) {
        if case .podcastEpisode(_, let current, _) = player.playbackType, current.id == item.episode.id {
            player.togglePlayPause()
            return
        }
        let episode = item.episode.asEpisode
        player.playPodcastEpisode(episode, podcast: podcast(item.podcast), queue: [episode], client: env.client)
    }
}
