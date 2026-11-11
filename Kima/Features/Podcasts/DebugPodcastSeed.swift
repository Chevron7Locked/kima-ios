#if DEBUG
import Foundation

/// DEBUG-only fixture for the podcast transport UI tests (`-kima-fake-podcast`, no trailing colon).
/// Feeds the seeded detail page (so hero + rows render with no server) and the seeded playback
/// session (so the transport mirrors read a true engine state). One source for both, like the
/// placeholder track JSON in `-kima-fake-now-playing`.
enum DebugPodcastSeed {
    /// "paused", "playing", "waiting" or "stopped" — the engine state the seeded session starts in.
    static var mode: String? { DebugDeepLink.launchArgValue("-kima-fake-podcast") }
    static var isActive: Bool { mode != nil }

    static let seedId = "seed-station"

    /// The seeded page's show. Five lowercase-letter titles keep the accessibility-label probes
    /// (which match on substring) from tripping over the page's own section headers.
    static let podcastJson =
        #"{"id":"seed-station","title":"seed station","author":"seed author","autoDownloadEpisodes":false,"episodeTotal":5,"episodes":[\#(episodesJson)]}"#

    static var queueJson: String { "[" + episodesJsonComponents.joined(separator: ",") + "]" }

    /// The bare comma-joined episode objects — podcastJson adds the surrounding brackets.
    private static var episodesJson: String { episodesJsonComponents.joined(separator: ",") }

    private static var episodesJsonComponents: [String] {
        [ #"{"id":"seed-1","title":"seed one","duration":260,"publishedAt":"2026-11-01T00:00:00.000Z","progress":{"currentTime":260,"progress":100.0,"isFinished":false,"lastPlayedAt":"2026-11-08T00:00:00.000Z"}}"#,
          #"{"id":"seed-2","title":"seed two","duration":260,"publishedAt":"2026-10-25T00:00:00.000Z"}"#,
          #"{"id":"seed-3","title":"seed three","duration":260,"publishedAt":"2026-10-18T00:00:00.000Z"}"#,
          #"{"id":"seed-4","title":"seed four","duration":260,"publishedAt":"2026-10-11T00:00:00.000Z"}"#,
          #"{"id":"seed-5","title":"seed five","duration":260,"publishedAt":"2026-10-04T00:00:00.000Z"}"# ]
    }
}
#endif
