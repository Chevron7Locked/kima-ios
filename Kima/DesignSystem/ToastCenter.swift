import Foundation
import Observation

// MARK: - Toast data types

/// Visual style of a toast banner (drawn by `KimaToastView`).
enum ToastStyle {
    /// Operation succeeded — green checkmark icon.
    case success
    /// Operation failed — red exclamation icon.
    case error
    /// Neutral information — muted info icon.
    case info
}

/// A button on a toast, e.g. "undo". Tapping it runs `perform` and closes the toast.
struct ToastAction {
    let label: String
    let perform: @MainActor () -> Void
}

/// Immutable snapshot of a single in-flight toast notification.
struct KimaToastData: Identifiable, Equatable {
    let id: UUID
    let message: String
    let style: ToastStyle
    let action: ToastAction?

    init(message: String, style: ToastStyle, action: ToastAction? = nil) {
        self.id      = UUID()
        self.message = message
        self.style   = style
        self.action  = action
    }

    static func == (a: KimaToastData, b: KimaToastData) -> Bool { a.id == b.id }
}

// MARK: - ToastCenter

/// App-wide transient-notification hub, owned by `AppShellView` and injected via `.environment(toastCenter)`. Any view
/// posts with `@Environment(ToastCenter.self)` then `toastCenter.show("Track added", style: .success)`.
/// Auto-dismisses after 2.5 s, or 5 s when it carries an action. A `show` while a toast is visible cancels the
/// pending dismiss and restarts the timer.
@MainActor
@Observable
final class ToastCenter {

    /// The currently-visible toast, or `nil` when no banner is shown.
    /// `KimaToastOverlay` observes this automatically via `@Observable` tracking.
    private(set) var current: KimaToastData?

    private var dismissTask: Task<Void, Never>?

    /// Post a transient notification banner. Call from the main actor.
    /// `message` should be concise (one line); `style` picks the icon colour (default `.info`).
    /// `action` adds a button such as "undo".
    func show(_ message: String, style: ToastStyle = .info, action: ToastAction? = nil) {
        dismissTask?.cancel()
        current = KimaToastData(message: message, style: style, action: action)

        dismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(action == nil ? 2.5 : 5))
                self?.current = nil
            } catch {
                // Cancelled — a newer show() has replaced this dismiss.
            }
        }
    }

    /// Runs the visible toast's action and closes the toast.
    func performAction() {
        guard let action = current?.action else { return }
        dismissTask?.cancel()
        current = nil
        action.perform()
    }
}
