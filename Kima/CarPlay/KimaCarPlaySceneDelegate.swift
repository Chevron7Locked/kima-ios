import CarPlay

// MARK: - KimaCarPlaySceneDelegate
// CarPlay scene entry point (named from Info.plist). Builds the home `CPListTemplate` on the shared `AppEnvironment`
// published by `RootView` via `CarPlayLink`, and rebuilds the root when it appears or disappears.
// `@MainActor` extends the framework's main-actor delegate isolation to the helper methods, like `CarPlayLink`.
@MainActor
@objc(KimaCarPlaySceneDelegate)
final class KimaCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?

    /// Token for the `CarPlayLink` observer registered in `didConnect`; removed in `didDisconnect`.
    private var envObserverId: UUID?

    /// In-flight home-screen list-load tasks (currently just the CONTINUE-section fetch).
    /// Cancelled on every rebuild (env change) and on disconnect so a stale fetch can never call
    /// `updateSections` using an `env`/`client` that has since gone away.
    private var loadTasks: [Task<Void, Never>] = []

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        // Hand the interface controller to the Now Playing configurator so the "Chapters" up-next
        // observer can push its chapter list. Observer registration itself happens lazily in
        // configure(env:) and is torn down in didDisconnect below.
        CarPlayNowPlaying.shared.attach(interfaceController: interfaceController)
        envObserverId = CarPlayLink.shared.observe { [weak self] in self?.rebuildRoot() }
        rebuildRoot()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        if let envObserverId {
            CarPlayLink.shared.removeObserver(envObserverId)
        }
        envObserverId = nil
        // Pairs the single addObserver in CarPlayNowPlaying.configure — the shared template
        // outlives this scene, so a missing removeObserver would leak + route taps to a dead
        // controller. detach() also drops the captured interface controller + chapter cache.
        CarPlayNowPlaying.shared.detach()
        cancelLoadTasks()
        self.interfaceController = nil
    }

    // MARK: - Root building

    /// Reads the current `CarPlayLink.shared.environment` and sets the appropriate root
    /// template: the auth gate when nil, or the full browse tree once signed in. Called once on
    /// connect and again every time the env appears/disappears (sign-in / sign-out on the phone).
    private func rebuildRoot() {
        guard let interfaceController else { return }
        cancelLoadTasks()

        guard let env = CarPlayLink.shared.environment else {
            interfaceController.setRootTemplate(CarPlayBrowse.buildAuthGateTemplate(), animated: true) { _, _ in }
            return
        }

        let (root, tasks) = CarPlayBrowse.buildRoot(env: env, interfaceController: interfaceController)
        loadTasks = tasks
        interfaceController.setRootTemplate(root, animated: true) { _, _ in }

        // Sync the Now Playing chrome (speed button + Chapters) to whatever is playing right now —
        // and keep it in sync as content changes — so it's present even when a book was already
        // playing (started on the phone) before CarPlay connected, not only after a CarPlay play.
        CarPlayNowPlaying.shared.activate(env: env)
    }

    private func cancelLoadTasks() {
        for task in loadTasks { task.cancel() }
        loadTasks.removeAll()
    }
}
