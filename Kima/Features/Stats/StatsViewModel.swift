import Foundation
import Observation

// MARK: - Stats page state
// One request and one period for the whole page, so every figure is comparable. Old figures stay on screen while
// a new period loads. A failed period switch keeps them and reconciles the control to the loaded period at render;
// it never writes `period` from the failure path, which would refire the load.

@Observable
@MainActor
final class StatsViewModel {
    private let client: KimaAPIClient

    private(set) var data: StatsResponse?
    private(set) var failed = false
    private(set) var reloading = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    var period: StatsPeriod = .all { didSet { if period != oldValue { load() } } }

    /// The period whose FIGURES are on screen: after a failed switch, the old
    /// one — the control follows this, not the tap.
    var shownPeriod: StatsPeriod {
        guard failed, let p = data?.period, let shown = StatsPeriod(rawValue: p) else { return period }
        return shown
    }

    init(client: KimaAPIClient) {
        self.client = client
    }

    func load() {
        loadTask?.cancel()
        loadTask = Task { await fetch() }
    }

    func retry() {
        failed = false
        load()
    }

    private func fetch() async {
        // The old figures stay visible; only a first load shows the skeleton.
        if data != nil { reloading = true }
        let requested = period
        do {
            let res = try await client.getStats(period: requested)
            guard !Task.isCancelled, requested == period else { return }
            data = res
            failed = false
        } catch {
            guard !Task.isCancelled, requested == period else { return }
            failed = true
        }
        reloading = false
    }
}
