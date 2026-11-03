import Foundation

// MARK: - Sleep timer: end-of-item end policies
// "Sleep after this item" policies (endOfTrack, endOfEpisode, endOfChapter; one chapter is one file). Checked at
// the top of handleEnded() (+Queue.swift), before repeat-one and long-form auto-advance, so repeat-one cannot
// defeat one. A policy is consumed only by an ending of its own type, so a visible policy is never dropped.

extension PlaybackController {

    /// Pause instead of advancing when the currently-playing item ends naturally,
    /// if an end-of-item sleep policy is armed for its type. Returns true when the
    /// policy just fired (caller must stop advancing); false = proceed normally.
    @discardableResult
    func consumeSleepAfterCurrentItem() -> Bool {
        let policy = sleepTimer.endPolicy
        guard policy != .timed else { return false }
        let matches: Bool
        switch playbackType {
        case .track:                 matches = policy == .endOfTrack
        case .podcastEpisode:        matches = policy == .endOfEpisode
        case .audiobook:             matches = policy == .endOfChapter
        }
        // A non-matching ending consumes nothing: the policy stays armed for an item of
        // its own type (switching music → podcast with "end of episode" armed sleeps at
        // that first episode's end, which is the plain-language meaning).
        guard matches else { return false }
        sleepTimer.endPolicy = .timed
        // Stop AFTER this item: line up the next one paused, so play carries on in the morning.
        switch playbackType {
        case .track:
            let (nextIdx, nextShufflePos) = computeNext()
            if repeatMode != .one, let nextIdx {
                currentIndex = nextIdx
                if let nextShufflePos { shufflePosition = nextShufflePos }
                loadCurrentTrack(autoplay: false)
                nowPlayingHook?()
                syncHook?()
            } else {
                pause()
                seek(to: 0)
            }
        case .audiobook:
            handleAudiobookFileEnded(autoplay: false)    // last file → finishAudiobook, as today
        case .podcastEpisode:
            handlePodcastEpisodeEnded(autoplay: false)   // last episode → pauses, as today
        }
        return true
    }
}
