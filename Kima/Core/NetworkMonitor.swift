import Foundation
import Network
import Observation

/// Monitors device-level network reachability using NWPathMonitor, exposed as `AppEnvironment.network`.
/// Path updates arrive on a private background queue and hop to the main actor immediately, so observers can
/// drive SwiftUI state directly. Starts on `init`, cancelled on `deinit`.
@MainActor
@Observable
final class NetworkMonitor {

    /// True while the device has at least one viable network path (Wi-Fi, cellular, or other).
    /// Initialised optimistically to `true`; the first NWPathMonitor callback corrects it
    /// if the device is already offline when the app launches.
    private(set) var isOnline: Bool = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Compute off the monitor's queue (no self needed here), then hop to the main actor
            // to publish — weak so a torn-down monitor can't resurrect self.
            var online = path.status == .satisfied
            #if DEBUG
            // Screenshot hook: show the offline state without cutting the network.
            if CommandLine.arguments.contains("-kima-fake-offline") { online = false }
            #endif
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "kima.network-monitor", qos: .utility))
    }

    deinit {
        monitor.cancel()
    }
}
