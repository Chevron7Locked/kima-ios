import Foundation

/// The reported-change state of the ServerTrust module — the one observable every certificate-alert
/// surface binds, injected through the environment rather than reached for as a global.
///
/// When a previously-pinned self-signed certificate changes (possible MITM), the module reports it
/// here. The UI shows one blocking alert at a time; changes for other hosts wait their turn.
@MainActor
@Observable
final class ServerTrustState {
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

    /// The module's answer to "trust the new certificate", installed by `ServerTrust` when it creates
    /// this state: forgets the host's pin and bumps the generation so in-flight challenges go quiet.
    private let onTrust: @Sendable (String) -> Void

    // Constructible off the main actor (SE-0327): the ServerTrust module owns this state and is built
    // where URLSession builds it. Starting values touch no isolated state, so producing one is safe.
    nonisolated init(onTrust: @escaping @Sendable (String) -> Void) {
        self.onTrust = onTrust
    }

    /// The user answered "trust the new certificate" for `host`. Like the alert's other buttons this
    /// only acts — closing the alert goes through the view's `isPresented` binding, once per alert.
    func trust(host: String) {
        onTrust(host)
    }

    /// Alert copies mounted inside sheet content, right now. While any live, the copy attached below
    /// sheets goes quiet: a sheet covers alert attachments under it, and two attachments fighting over
    /// one presentation end with the loser's teardown writing `isPresented = false` — clearing a change
    /// nobody answered (the sheet case in `CertificateAlertUITests` proves it on the real view tree).
    /// Each copy declares only its own intrinsic position; the coordination lives here.
    private var overlayAttachments = 0

    /// An alert attachment appeared; `overlay` means it lives inside sheet content.
    func attachAlert(overlay: Bool) { if overlay { overlayAttachments += 1 } }

    /// An alert attachment went away.
    func detachAlert(overlay: Bool) { if overlay { overlayAttachments = max(0, overlayAttachments - 1) } }

    /// Whether an alert copy on this side of the sheet boundary may present the shown change: a copy
    /// inside a live sheet takes precedence; the root-side copy presents only while no such copy lives.
    func canPresent(overlay: Bool) -> Bool {
        shown != nil && (overlay || overlayAttachments == 0)
    }

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
