import Foundation

// MARK: - CarPlayLink

/// Process-level bridge so the CarPlay scene (a separate `UIScene` with no SwiftUI view tree) can reach the same
/// `AppEnvironment` and `PlaybackController` as the phone window; two players would double the audio.
/// `RootView` publishes the env here; the scene delegate reads `environment` and rebuilds templates via `observe`
/// when it appears or disappears. CarPlay never builds its own env or player. `@MainActor`: callbacks hop to main.
@MainActor
final class CarPlayLink {
    static let shared = CarPlayLink()
    private init() {}

    /// The live environment, or `nil` before the user has connected + authenticated. CarPlay shows
    /// a "connect on your iPhone" template while this is nil.
    private(set) var environment: AppEnvironment?

    /// CarPlay-side change callbacks, keyed so they can be removed on scene disconnect.
    private var observers: [UUID: () -> Void] = [:]

    /// Called by RootView when the environment is built (auth) or cleared (sign-out). Idempotent.
    func publish(_ env: AppEnvironment?) {
        guard env !== environment else { return }
        environment = env
        for callback in observers.values { callback() }
    }

    /// Register a callback fired whenever `environment` changes. Returns a token for removal.
    @discardableResult
    func observe(_ callback: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        return id
    }

    func removeObserver(_ id: UUID) { observers[id] = nil }
}
