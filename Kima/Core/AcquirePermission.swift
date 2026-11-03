import Foundation
import Observation

/// Whether this listener may start downloads (GET /system-settings/public-config `canAcquire`). Downloading is
/// operator-only unless an admin allows members, and the server refuses the request either way; this only decides
/// whether download controls are offered. False until the server has answered, so no control flashes in and out.
@MainActor
@Observable
final class AcquirePermission {
    /// The server said this listener may start downloads.
    private(set) var canAcquire = false
    /// The server answered that this listener may not.
    private(set) var isLocked = false

    /// The one wording for a member who can't start downloads (the web's ACQUIRE_LOCKED_LABEL).
    static let lockedLabel = "downloads are operator-only"

    @ObservationIgnored private var checkedAt: Date?

    /// The toast for a failed download: the operator-only wording when the server refused it (403),
    /// otherwise `fallback`.
    static func failureMessage(_ error: Error, fallback: String) -> String {
        if case APIError.http(status: 403, _) = error { return lockedLabel }
        return fallback
    }

    /// Asks the server at most every five minutes. A server without the route (404) predates the operator-only rule
    /// and allows downloads. Any other failed ask, including an answer the app can't read, keeps the last answer and
    /// tries again next time.
    func refresh(client: KimaAPIClient) async {
        if let checkedAt, Date().timeIntervalSince(checkedAt) < 300 { return }
        let allowed: Bool
        do {
            allowed = try await client.getPublicConfig().canAcquire
        } catch APIError.http(status: 404, _) {
            allowed = true
        } catch {
            return
        }
        canAcquire = allowed
        isLocked = !allowed
        checkedAt = Date()
    }
}
