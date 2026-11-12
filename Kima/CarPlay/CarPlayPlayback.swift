import Foundation

// MARK: - CarPlayPlayback
//
// Tap → player mapping for the browse tree. Every entry point drives `env.player`, the same `PlaybackController`
// the phone uses (via `CarPlayLink`); CarPlay never builds its own player. No CarPlay-framework import here.

@MainActor
enum CarPlayPlayback {

    /// Audiobooks and Continue both route through this. The already-loaded guard is the shared
    /// dispatch's decision, not CarPlay's (ticket 06's entry point, awaited form): while this
    /// book holds the session the tap resumes-or-pauses through the transport's precedence and
    /// nothing is fetched — a reload re-seeks and, if the fetched detail's `progress` comes back
    /// nil, would restart the book at 0 over your real place (the double-tap bug). Not owned →
    /// re-fetches full detail first so `Audiobook.progress` is populated: list responses don't
    /// reliably carry it, and `playAudiobook` needs it to resume at the saved position
    /// (`makeBookSession` fetches tracks but not progress). False when the book couldn't be
    /// fetched (the caller says so).
    @discardableResult
    static func playAudiobook(id: String, resumeAt: Double? = nil, env: AppEnvironment) async -> Bool {
        var loadFailed = false
        await env.player.handleHeroTap(bookId: id) {
            guard let book = try? await env.client.getAudiobook(id: id) else {
                loadFailed = true
                return
            }
            await env.player.playAudiobook(book, client: env.client, resumeAt: resumeAt)
        }
        return !loadFailed
    }

    /// Force-reload `id` at `resumeAt`, bypassing the shared dispatch's same-book guard that
    /// `playAudiobook(id:resumeAt:env:)` routes through. Used by "Start
    /// Over" (`resumeAt: 0`) and chapter rows (the chapter's book-absolute start), where the book may already be current
    /// but the user wants a re-seek, not a no-op. False when the book couldn't be fetched (the caller says so).
    @discardableResult
    static func restartAudiobook(id: String, at resumeAt: Double = 0, env: AppEnvironment) async -> Bool {
        guard let book = try? await env.client.getAudiobook(id: id) else { return false }
        await env.player.playAudiobook(book, client: env.client, resumeAt: resumeAt)
        return true
    }

    /// Podcasts tab: `episode` + `podcast` + `queue` are already in memory (fetched together via
    /// `getPodcast(id:)` when the episode list was pushed), so this is a synchronous hand-off.
    static func playPodcastEpisode(_ episode: Episode, podcast: Podcast, queue: [Episode], env: AppEnvironment) {
        env.player.playPodcastEpisode(episode, podcast: podcast, queue: queue, client: env.client)
    }

    /// Playlists tab: `items` is the FULL (untruncated) track list for the playlist, even when
    /// the visible CarPlay rows were capped for the list-item limit — the player queue should
    /// still contain every track so skip/next behaves like the phone app.
    static func playPlaylistTrack(at index: Int, items: [PlaylistItem], env: AppEnvironment) {
        env.player.play(tracks: items.map(\.asTrack), startAt: index)
    }
}
