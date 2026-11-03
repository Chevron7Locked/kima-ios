import Foundation

// MARK: - Notification Models

/// Optional deep-link fields from `notification.metadata`.
/// Only the keys the UI actually uses are decoded; all other fields are silently ignored.
struct NotificationMetadata: Codable {
    let playlistId: String?
    let albumId: String?
    let artistId: String?
    let artistName: String?
    let albumTitle: String?
}

/// A user-facing in-app notification, shaped like the Prisma `Notification` model. `cleared` is included because
/// some SSE payloads embed the full record; the server already filters them from GET /notifications and
/// SSEManager filters locally as a safety net.
struct KimaNotification: Codable, Identifiable {
    let id: String
    let type: String
    let title: String
    let message: String?
    let metadata: NotificationMetadata?
    let read: Bool
    let cleared: Bool
    let createdAt: String

    /// Returns a copy with `read` toggled for optimistic local updates.
    func with(read newRead: Bool) -> KimaNotification {
        KimaNotification(
            id: id, type: type, title: title, message: message,
            metadata: metadata, read: newRead, cleared: cleared, createdAt: createdAt
        )
    }
}

/// A completed or failed download history entry.
///
/// Shape: `DownloadJob` Prisma model via GET /api/notifications/downloads/history.
/// Note: `getActiveDownloads()` (active-only list) lives in KimaAPIClient+Downloads.swift.
struct DownloadHistoryItem: Codable, Identifiable {
    let id: String
    let subject: String
    let type: String
    let status: String
    let error: String?
    let createdAt: String
    let completedAt: String?
}

// MARK: - Import Model

/// A Spotify → Kima playlist import job.
///
/// Shape: `ImportJob` Prisma model via GET /api/spotify/imports.
struct ImportJob: Codable, Identifiable {
    let id: String
    let playlistName: String
    let status: String
    let albumsTotal: Int
    let albumsCompleted: Int
    let error: String?
    let createdAt: String
}
