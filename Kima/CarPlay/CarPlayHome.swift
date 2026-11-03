import CarPlay
import UIKit

// MARK: - CarPlayHome
//
// The home screen's NOW PLAYING card: one cover-forward row for whatever `env.player` has
// loaded; tapping it pushes the shared Now Playing template. nil (section omitted) when nothing plays.

extension CarPlayBrowse {

    /// nil when nothing is loaded in the player — `buildRoot` omits the whole section in that case.
    static func nowPlayingSection(
        env: AppEnvironment, interfaceController: CPInterfaceController
    ) -> CPListSection? {
        guard let card = nowPlayingCard(env: env) else { return nil }

        let row = CPListItem(text: card.title, detailText: card.subtitle, image: CarPlayArtwork.placeholder)
        row.accessoryType = .disclosureIndicator
        row.handler = { _, completion in
            pushNowPlaying(on: interfaceController)
            completion()
        }
        if let coverURL = card.coverURL {
            attachArtwork(to: row, url: coverURL, interfaceController: interfaceController)
        } else if let coverId = card.coverId {
            attachArtwork(to: row, coverId: coverId, env: env, interfaceController: interfaceController)
        }
        return CPListSection(items: [row], header: "now playing", sectionIndexTitle: nil)
    }

    // MARK: - Current-item snapshot

    private struct NowPlayingCard {
        let title: String
        let subtitle: String?
        let coverURL: URL?
        let coverId: String?
    }

    /// Reads whatever `env.player` currently holds. Audiobook/podcast metadata comes from
    /// `longFormNowPlayingMeta` (populated whenever long-form playback starts, including a book
    /// resumed on the phone before CarPlay connected — see `CarPlayNowPlaying.activate`); music
    /// comes straight off the queue's `currentTrack`. Nil when the player is truly idle.
    private static func nowPlayingCard(env: AppEnvironment) -> NowPlayingCard? {
        switch env.player.playbackType {
        case .audiobook:
            guard let meta = env.player.longFormNowPlayingMeta else { return nil }
            return NowPlayingCard(
                title: meta.title, subtitle: "audiobook · \(meta.artist)",
                coverURL: meta.coverURL, coverId: nil
            )
        case .podcastEpisode:
            guard let meta = env.player.longFormNowPlayingMeta else { return nil }
            return NowPlayingCard(
                title: meta.title, subtitle: meta.artist,
                coverURL: meta.coverURL, coverId: nil
            )
        case .track:
            guard let track = env.player.currentTrack else { return nil }
            return NowPlayingCard(
                title: track.effectiveTitle, subtitle: track.artist?.name,
                coverURL: nil, coverId: track.album?.coverArt
            )
        }
    }
}
