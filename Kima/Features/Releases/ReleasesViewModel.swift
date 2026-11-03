import Foundation
import Observation

// MARK: - ReleasesViewModel
//
// Release Radar: upcoming and recent releases for the user's Lidarr-monitored artists and related artists,
// from GET /api/releases/radar.

@MainActor
@Observable
final class ReleasesViewModel {

    // MARK: Observable state

    var phase: LoadPhase<ReleasesRadarResponse> = .loading
    /// albumMbids of releases currently being downloaded (in-flight POST).
    var downloadingMbids: Set<String> = []

    // MARK: Computed

    var radar: ReleasesRadarResponse? {
        if case .loaded(let r) = phase { return r }
        return nil
    }

    var upcoming: [ReleaseItem] { radar?.upcoming ?? [] }
    var recent: [ReleaseItem]   { radar?.recent   ?? [] }

    // MARK: Load

    /// false = a refetch failed and the previous releases were kept.
    @discardableResult
    func load(using client: KimaAPIClient) async -> Bool {
        do {
            phase = .loaded(try await client.releasesRadar())
            return true
        } catch {
            if Task.isCancelled { return true }
            if case .loaded = phase { return false }
            phase = .failed(error.localizedDescription)
            return true
        }
    }

    // MARK: Download

    /// Triggers a download for `release` and returns a (message, isError) tuple describing the outcome; never throws.
    /// Progress is not polled here: the server returns a `jobId` for a job it has already created, and that job
    /// appears in the Downloads/Activity panel (`ActiveDownloadsViewModel`) by its own id.
    func download(release: ReleaseItem, using client: KimaAPIClient) async -> (message: String, isError: Bool) {
        guard !downloadingMbids.contains(release.albumMbid) else {
            return ("already queued", false)
        }
        downloadingMbids.insert(release.albumMbid)
        defer { downloadingMbids.remove(release.albumMbid) }
        do {
            let response = try await client.downloadRelease(
                albumMbid: release.albumMbid,
                artistName: release.artistName,
                albumTitle: release.title
            )
            return (response.message ?? "download queued for \(release.title)", false)
        } catch {
            return (AcquirePermission.failureMessage(error, fallback: "couldn't start download"), true)
        }
    }
}
