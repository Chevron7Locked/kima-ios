import Foundation
import Observation

/// Every step of linking this device from a link-a-device QR code. A link never sends anything by
/// itself: the request goes out only from `confirm()`, after the person has seen the server host.
@MainActor
@Observable
final class DevicePairingViewModel {
    enum Step: Equatable {
        case scanning
        case confirm(DevicePairingLink)
        case waiting(DevicePairingLink)
        /// Linked; the sheet is on its way out. Keeps the sheet from flashing "already signed in" as the session flips.
        case linked
        case failed(message: String, retry: DevicePairingLink?)
    }

    private(set) var step: Step
    /// Shown over the scanner when a QR code is not a kima link.
    private(set) var scanHint: String?

    private let linker: DeviceLinker
    private let currentPhase: @MainActor () -> SessionStore.Phase
    private let onLinked: @MainActor () -> Void
    private(set) var linkTask: Task<Void, Never>?

    init(request: DevicePairingRequest,
         linker: DeviceLinker? = nil,
         currentPhase: @escaping @MainActor () -> SessionStore.Phase,
         onLinked: @escaping @MainActor () -> Void) {
        self.linker = linker ?? DeviceLinker()
        self.currentPhase = currentPhase
        self.onLinked = onLinked
        switch request {
        case .scan: step = .scanning
        case .link(let link): step = .confirm(link)
        case .invalid: step = .failed(message: "that isn't a valid kima link.", retry: nil)
        }
    }

    /// Linking replaces the stored login, so it is allowed only when there is no live session.
    static func canLink(in phase: SessionStore.Phase) -> Bool {
        switch phase {
        case .unauthenticated, .unreachable: return true
        case .launching, .authenticated: return false
        }
    }

    /// A string read from a QR code. Returns true when it was a valid link, which stops the scanner.
    @discardableResult
    func scanned(_ payload: String) -> Bool {
        guard step == .scanning else { return false }
        switch DevicePairingLink.parse(payload) {
        case .link(let link):
            scanHint = nil
            step = .confirm(link)
            return true
        case .invalid:
            scanHint = "that code isn't a valid kima link."
        case .notPairing:
            scanHint = "that isn't a kima code."
        }
        return false
    }

    func confirm() {
        guard case .confirm(let link) = step else { return }
        send(link)
    }

    func retry() {
        guard case .failed(_, let link?) = step else { return }
        send(link)
    }

    func scanAgain() {
        scanHint = nil
        step = .scanning
    }

    /// Hangs up on the server, which frees the code. Writes nothing and shows no error.
    func cancel() {
        linkTask?.cancel()
        linkTask = nil
        if case .waiting(let link) = step { step = .confirm(link) }
    }

    private func send(_ link: DevicePairingLink) {
        guard !link.isLoopback, Self.canLink(in: currentPhase()) else { return }
        step = .waiting(link)
        linkTask = Task { [linker] in
            let result = await linker.link(code: link.code, server: link.server)
            guard !Task.isCancelled, case .waiting = step else { return }
            switch result {
            case .linked:
                step = .linked
                onLinked()
            case .cancelled: break
            case .failed(let message, let canRetry):
                step = .failed(message: message, retry: canRetry ? link : nil)
            }
        }
    }
}
