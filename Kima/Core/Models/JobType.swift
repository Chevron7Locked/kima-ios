import Foundation

// MARK: - Job type

/// The one mapping from a job's server `type` string ("album" | "artist") to its SF Symbol.
/// Spelled once, here; every job row (active downloads, download history) consumes it.
enum JobType {
    static func symbol(for type: String) -> String {
        type == "album" ? "opticaldisc" : "music.mic"
    }
}
