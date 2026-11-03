import Foundation
import Observation
import os

private let libraryLog = Logger(subsystem: "com.chevron7locked.kima", category: "library")

// MARK: - LibraryShelfSummary

/// How much of the library has been heard, for the library masthead (`getShelfStats`), kept for ten minutes so
/// returning to the tab costs nothing.
@MainActor
@Observable
final class LibraryShelfSummary {
    private(set) var shelf: ShelfStats?
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var isLoading = false

    static let maxAge: TimeInterval = 10 * 60

    /// Fetches unless a fresh copy is held; `force` (pull to refresh) always fetches. A failure keeps the last copy.
    func load(using client: KimaAPIClient, force: Bool = false, now: Date = .now) async {
        if !force, let at = fetchedAt, now.timeIntervalSince(at) < Self.maxAge { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let clock = ContinuousClock()
        let started = clock.now
        guard let shelf = try? await client.getShelfStats() else { return }
        libraryLog.debug("library summary: GET /stats took \(Int((clock.now - started) / .milliseconds(1))) ms")
        self.shelf = shelf
        fetchedAt = now
    }

    /// The masthead line, e.g. "7% of library played · 6,412 tracks never played"; nil until loaded.
    var heardLine: String? {
        guard let shelf, shelf.tracks.total > 0 else { return nil }
        let pct = StatsFormat.percent(part: shelf.tracks.heard, whole: shelf.tracks.total)
        let never = shelf.neverPlayed
        guard never > 0 else { return "\(pct)% of library played" }
        return "\(pct)% of library played · \(never.formatted(.number)) \(never == 1 ? "track" : "tracks") never played"
    }
}
