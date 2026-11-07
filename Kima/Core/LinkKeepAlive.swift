import UIKit

/// Keeps the phone awake and the app alive while a link request waits for the person to approve it,
/// which they do on another screen (sometimes Safari on this same phone).
@MainActor
enum LinkKeepAlive {
    private final class TaskBox { var id = UIBackgroundTaskIdentifier.invalid }

    static func during<T>(_ work: () async throws -> T) async rethrows -> T {
        let app = UIApplication.shared
        let wasIdleDisabled = app.isIdleTimerDisabled
        app.isIdleTimerDisabled = true
        let box = TaskBox()
        box.id = app.beginBackgroundTask(withName: "kima.device-link") {
            app.endBackgroundTask(box.id)
            box.id = .invalid
        }
        defer {
            app.isIdleTimerDisabled = wasIdleDisabled
            if box.id != .invalid { app.endBackgroundTask(box.id) }
        }
        return try await work()
    }
}
