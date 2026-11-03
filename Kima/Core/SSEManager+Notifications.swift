import Foundation

// MARK: - SSEManager notification actions
//
// Wraps the notification endpoints with the `notifications` / `unreadCount` state SSEManager owns. Split out so
// the main file stays on SSE stream transport.

extension SSEManager {

    // MARK: - Notification refresh

    /// Reloads the full notification list from the server and syncs `unreadCount`. Best-effort: errors are ignored
    /// so the stream loop keeps running. Single-flight: returns immediately if a refresh is already running,
    /// whose result serves all callers.
    func refreshNotifications() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        guard let client = storedClient else { return }
        do {
            let items = try await client.getNotifications()
            // Server already excludes cleared items; filter locally as a safety net.
            notifications = items.filter { !$0.cleared }
            unreadCount = notifications.filter { !$0.read }.count
        } catch {
            // best-effort — keep existing state on transient network errors
        }
    }

    // MARK: - Notification actions (optimistic local update + server sync)

    /// Mark one notification read. Updates local state immediately; fires network call async.
    func markRead(id: String) async {
        notifications = notifications.map { $0.id == id ? $0.with(read: true) : $0 }
        unreadCount = notifications.filter { !$0.read }.count
        do { _ = try await storedClient?.markNotificationRead(id: id) } catch { await refreshNotifications() }
    }

    /// Mark all notifications read.
    func markAllRead() async {
        notifications = notifications.map { $0.with(read: true) }
        unreadCount = 0
        do { _ = try await storedClient?.markAllNotificationsRead() } catch { await refreshNotifications() }
    }

    /// Dismiss (clear) a single notification.
    func clear(id: String) async {
        notifications = notifications.filter { $0.id != id }
        unreadCount = notifications.filter { !$0.read }.count
        do { _ = try await storedClient?.clearNotification(id: id) } catch { await refreshNotifications() }
    }

    /// Dismiss all notifications.
    func clearAll() async {
        notifications = []
        unreadCount = 0
        do { _ = try await storedClient?.clearAllNotifications() } catch { await refreshNotifications() }
    }
}
