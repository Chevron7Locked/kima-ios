import Foundation

/// Observable shared state for the TOFU server-trust coordinator.
///
/// When a previously-pinned self-signed certificate changes (possible MITM), the coordinator
/// reports it here. The UI shows one blocking alert at a time; changes for other hosts wait their turn.
@MainActor
@Observable
final class ServerTrustState {
    static let shared = ServerTrustState()

    /// A pinned certificate that changed, waiting for the user to answer.
    struct Change: Equatable {
        let host: String
        /// False when the certificate kept its key but no longer names this host: trusting it again
        /// can't help (the name check would still fail), so the alert offers no trust button.
        let keyChanged: Bool
    }

    /// The change the alert shows now.
    private(set) var shown: Change?

    /// Changes for other hosts, in the order they were reported.
    private(set) var waiting: [Change] = []

    init() {}

    /// Queue an alert for `host`, unless one for that host is already showing or waiting.
    func report(host: String, keyChanged: Bool) {
        guard shown?.host != host, !waiting.contains(where: { $0.host == host }) else { return }
        let change = Change(host: host, keyChanged: keyChanged)
        if shown == nil, waiting.isEmpty { shown = change } else { waiting.append(change) }
    }

    /// How long a closed alert gets to finish closing before the next one opens.
    var nextAlertDelay: Duration = .milliseconds(400)

    /// The pending opening of the next waiting change, if one is scheduled.
    private(set) var advance: Task<Void, Never>?

    /// The shown alert closed; the next waiting change opens after `nextAlertDelay`.
    func dismissShown() {
        shown = nil
        guard advance == nil, !waiting.isEmpty else { return }
        advance = Task { [weak self] in
            try? await Task.sleep(for: self?.nextAlertDelay ?? .zero)
            self?.advance = nil
            self?.showNext()
        }
    }

    /// Show the next waiting change, if the alert is free.
    func showNext() {
        guard shown == nil, !waiting.isEmpty else { return }
        shown = waiting.removeFirst()
    }
}
