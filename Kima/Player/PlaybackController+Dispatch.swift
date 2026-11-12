import Foundation

// MARK: - PlaybackController tap dispatch (ticket 06)
//
// The one place a content hero's tap is decided. A page hands over its membership rule (which
// tracks are its own) and the tap; whether that means resume, pause or start fresh is decided
// here — identity dispatches, never appearance (ADR 0001). Pages keep no branch of their own:
// a future change to this rule lands in this file.
//
// The membership questions dispatch consumes — one per kind: `ownsSession(forTrackIds:)`,
// `ownsSession(where:)`, `ownsPodcastSession(_:)`, `isAudiobookLoaded(_:)`. A new membership
// question greps this list first and joins it, so the family keeps one version of each.

extension PlaybackController {

    /// The hero-tap dispatch for pages whose membership is a track-id set (album, playlist,
    /// discover): owned → `togglePlayPause()` (audible pauses, paused resumes at position);
    /// otherwise the given tracks start fresh.
    func handleHeroTap(trackIds: Set<String>, tracks: [Track], shuffle: Bool? = nil) {
        dispatchHeroTap(owned: ownsSession(forTrackIds: trackIds)) {
            play(tracks: tracks, startAt: 0, shuffle: shuffle)
        }
    }

    /// The hero-tap dispatch for pages whose membership is their own rule over a track (artist):
    /// the page hands over the predicate and its start action; holding the session decides
    /// resume-vs-start-over, evaluated against session identity, never appearance (ADR 0001).
    func handleHeroTap(owns isIn: (Track) -> Bool, start: () -> Void) {
        dispatchHeroTap(owned: ownsSession(where: isIn), start: start)
    }

    /// The hero-tap dispatch for the podcast detail hero: the show question (`ownsPodcastSession`
    /// — which show holds the episode session) decides resume-vs-play-latest; the page keeps the
    /// play-latest action, never the decision.
    func handleHeroTap(podcastId: String, start: () -> Void) {
        dispatchHeroTap(owned: ownsPodcastSession(podcastId), start: start)
    }

    /// The hero-tap dispatch for the audiobook heroes (detail, series): the book question
    /// (`isAudiobookLoaded` — which book holds the session) decides resume-vs-start; the page
    /// keeps its play-book action, never the decision.
    func handleHeroTap(bookId: String, start: () -> Void) {
        dispatchHeroTap(owned: isAudiobookLoaded(bookId), start: start)
    }

    /// The awaited form of the book question, for pages whose start action must fetch before it
    /// can play (CarPlay's book rows re-fetch detail so `progress` is populated): the same one
    /// decision through the same core. When the controller chooses start, the awaited action
    /// runs after dispatch returns; an owned tap never reaches it — a surface that cannot wipe
    /// your position by re-fetching what it already holds (ticket 07's double-tap guard).
    func handleHeroTap(bookId: String, start: () async -> Void) async {
        var startsFresh = false
        dispatchHeroTap(owned: isAudiobookLoaded(bookId)) { startsFresh = true }
        if startsFresh { await start() }
    }

    /// The one decision every hero form funnels through: holding the session → the transport's
    /// own precedence (`togglePlayPause()` — audible pauses, paused resumes at position);
    /// otherwise the page's action starts fresh. A future change to this rule lands here alone.
    private func dispatchHeroTap(owned: Bool, start: () -> Void) {
        if owned {
            togglePlayPause()
        } else {
            start()
        }
    }
}
