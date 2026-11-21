import Foundation

// MARK: - BookSession
// Presents a multi-file audiobook as one "book-time" timeline, and holds which of its files is loaded
// in the engine: every book time read from the engine, and every file change, goes through here.
// `files` MUST be sorted by startOffset ascending and non-empty; PlaybackController+LongFormHelpers
// enforces this before constructing a session.

/// Where a book time lands: its file, the time within that file, and whether that file was the
/// one already loaded (a seek within it, rather than a new stream).
struct BookLoad: Sendable {
    let file: AudiobookTrack
    let fileTime: Double
    let isSameFile: Bool
}

struct BookSession: Sendable {
    let bookId: String
    let totalDuration: Double       // sum of all file durations
    let files: [AudiobookTrack]     // sorted by startOffset; ≥1 file

    /// 1-based `AudiobookTrack.index` of the file loaded in the engine; 0 before the first load.
    /// Set when a load is issued, before its async hop, so the file in flight is the loaded one.
    private(set) var loadedFileIndex: Int

    init(bookId: String, totalDuration: Double, files: [AudiobookTrack], loadedFileIndex: Int = 0) {
        self.bookId = bookId
        self.totalDuration = totalDuration
        self.files = files
        self.loadedFileIndex = loadedFileIndex
    }

    // MARK: - The loaded file

    /// The file loaded in the engine; nil before the first load.
    var loadedFile: AudiobookTrack? { files.first { $0.index == loadedFileIndex } }

    /// The engine's time in the loaded file, as seconds into the book. With no file loaded the
    /// engine's time stands.
    func bookTime(engineTime: Double) -> Double {
        (loadedFile?.startOffset ?? 0) + engineTime
    }

    /// Load the file `bookTime` falls in (clamped to the book). The returned value says whether
    /// that file was already loaded.
    @discardableResult
    mutating func load(at bookTime: Double) -> BookLoad {
        let (file, fileTime) = locate(bookTime: bookTime)
        let isSameFile = file.index == loadedFileIndex
        loadedFileIndex = file.index
        return BookLoad(file: file, fileTime: fileTime, isSameFile: isSameFile)
    }

    /// The file after the loaded one; nil when the loaded file is the last (or none is loaded).
    var fileAfterLoaded: AudiobookTrack? {
        guard let i = files.firstIndex(where: { $0.index == loadedFileIndex }),
              files.indices.contains(i + 1)
        else { return nil }
        return files[i + 1]
    }

    /// The loaded file ended: load the next one. Nil when there is none — the book is finished,
    /// and the last file stays loaded.
    mutating func advanceFile() -> AudiobookTrack? {
        guard let next = fileAfterLoaded else { return nil }
        loadedFileIndex = next.index
        return next
    }

    // MARK: - Timeline

    /// Given a book-absolute time, return the file it falls in and the time-within-that-file.
    /// Clamps `bookTime` to [0, totalDuration].
    private func locate(bookTime: Double) -> (file: AudiobookTrack, fileTime: Double) {
        let clamped = max(0, min(bookTime, totalDuration))
        var best = files[0]
        for f in files {
            guard f.startOffset <= clamped else { break }
            best = f
        }
        return (best, fileTime(bookTime: bookTime, in: best))
    }

    /// `bookTime` as a time within `file`, kept inside the file. Clamps `bookTime` to [0, totalDuration].
    func fileTime(bookTime: Double, in file: AudiobookTrack) -> Double {
        let clamped = max(0, min(bookTime, totalDuration))
        return max(0, min(clamped - file.startOffset, file.duration))
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
