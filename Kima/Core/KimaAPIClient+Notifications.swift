import Foundation

// MARK: - Notifications API
// GET /api/notifications lists non-cleared items; /unread-count returns { count }; /downloads/history returns
// completed and failed jobs. POST /:id/read and /read-all mark read; POST /:id/clear and /clear-all dismiss.

/// Shared mutation response. `success` is marked optional to be resilient against
/// servers that omit the field on older API versions.
private struct NotificationSuccessResponse: Decodable {
    let success: Bool?
}

// MARK: - KimaAPIClient extension

extension KimaAPIClient {

    // MARK: Fetch

    /// GET /api/notifications — all non-cleared notifications for the current user.
    func getNotifications() async throws -> [KimaNotification] {
        try await get("/notifications", authed: true)
    }


    // MARK: Mark read

    /// POST /api/notifications/:id/read — mark a single notification read.
    @discardableResult
    func markNotificationRead(id: String) async throws -> Bool {
        try await postSuccess("/notifications/\(id)/read")
    }

    /// POST /api/notifications/read-all — mark every notification read.
    @discardableResult
    func markAllNotificationsRead() async throws -> Bool {
        try await postSuccess("/notifications/read-all")
    }

    // MARK: Clear

    /// POST /api/notifications/:id/clear — dismiss (clear) a single notification.
    @discardableResult
    func clearNotification(id: String) async throws -> Bool {
        try await postSuccess("/notifications/\(id)/clear")
    }

    /// POST /api/notifications/clear-all — dismiss all notifications.
    @discardableResult
    func clearAllNotifications() async throws -> Bool {
        try await postSuccess("/notifications/clear-all")
    }

    // MARK: Download history

    /// GET /api/notifications/downloads/history — completed and failed download jobs.
    func getDownloadHistory() async throws -> [DownloadHistoryItem] {
        try await get("/notifications/downloads/history", authed: true)
    }

    /// POST /api/notifications/downloads/:id/clear — remove one job from history view.
    @discardableResult
    func clearDownloadHistoryItem(id: String) async throws -> Bool {
        try await postSuccess("/notifications/downloads/\(id)/clear")
    }

    /// POST /api/notifications/downloads/clear-all — remove all completed/failed from history.
    @discardableResult
    func clearAllDownloadHistory() async throws -> Bool {
        try await postSuccess("/notifications/downloads/clear-all")
    }

    /// POST /api/notifications/downloads/:id/retry — requeue a failed download job.
    @discardableResult
    func retryDownload(id: String) async throws -> Bool {
        try await postSuccess("/notifications/downloads/\(id)/retry")
    }

    // MARK: Imports

    /// GET /api/spotify/imports — all import jobs for the current user.
    func getUserImports() async throws -> [ImportJob] {
        try await get("/spotify/imports", authed: true)
    }

    /// POST /api/spotify/import/:id/cancel — cancel an active import job.
    @discardableResult
    func cancelImport(id: String) async throws -> Bool {
        try await postSuccess("/spotify/import/\(id)/cancel")
    }

    // MARK: Private helpers

    /// POST to `path` with an empty body; returns `success` (defaults to `true` when absent).
    /// Routes 8 mark/clear/retry/cancel endpoints that differ only in path through one impl.
    private func postSuccess(_ path: String) async throws -> Bool {
        let r: NotificationSuccessResponse = try await post(path, body: [:], authed: true)
        return r.success ?? true
    }
}
