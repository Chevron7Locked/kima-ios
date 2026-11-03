import Foundation

// MARK: - BookSession
// Presents a multi-file audiobook as one "book-time" timeline.
// `files` MUST be sorted by startOffset ascending and non-empty; PlaybackController+LongForm enforces this
// before constructing a session.

struct BookSession: Sendable {
    let bookId: String
    let totalDuration: Double       // sum of all file durations
    let files: [AudiobookTrack]     // sorted by startOffset; ≥1 file

    // MARK: - Core operations

    /// Given a book-absolute time, return the file it falls in and the time-within-that-file.
    /// Clamps `bookTime` to [0, totalDuration].
    func locate(bookTime: Double) -> (file: AudiobookTrack, fileTime: Double) {
        let clamped = max(0, min(bookTime, totalDuration))
        var best = files[0]
        for f in files {
            guard f.startOffset <= clamped else { break }
            best = f
        }
        let fileTime = max(0, min(clamped - best.startOffset, best.duration))
        return (best, fileTime)
    }

    /// True when `file` is the last file in this session.
    func isLastFile(_ file: AudiobookTrack) -> Bool {
        file.index == files.last?.index
    }

    /// Look up a file by its 1-based `AudiobookTrack.index`. Returns nil when not found.
    func fileByIndex(_ index: Int) -> AudiobookTrack? {
        files.first { $0.index == index }
    }

    /// Return the file that comes after `current` in sorted order, or nil if `current` is last.
    func nextFile(after current: AudiobookTrack) -> AudiobookTrack? {
        guard let i = files.firstIndex(where: { $0.index == current.index }),
              files.indices.contains(i + 1)
        else { return nil }
        return files[i + 1]
    }
}

// MARK: - LongFormNowPlayingMeta

/// Minimal now-playing metadata for long-form content (audiobook / podcast episode).
/// Stored on `PlaybackController` so `NowPlayingController` can build the lock-screen
/// card even when `currentTrack == nil`.
struct LongFormNowPlayingMeta: Sendable {
    let title: String           // audiobook title or episode title
    let artist: String          // audiobook author or podcast show title
    /// Resolved cover-art URL (audiobook cover, or episode image falling back to podcast
    /// cover). Nil when the item has no art or `CoverArtURL` couldn't build a URL — the
    /// lock screen / CarPlay Now Playing simply shows no artwork in that case.
    let coverURL: URL?
}
