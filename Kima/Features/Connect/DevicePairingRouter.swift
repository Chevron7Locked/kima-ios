import Foundation

/// What opened the link-a-device sheet.
enum DevicePairingRequest: Equatable {
    /// "scan qr code" tapped in the app.
    case scan
    /// A `kima://link` URL opened from outside the app, e.g. the Camera app.
    case link(DevicePairingLink)
    /// A `kima://link` URL that failed validation; the sheet says so rather than doing nothing.
    case invalid

    init?(url: URL) {
        switch DevicePairingLink.parse(url) {
        case .notPairing: return nil
        case .invalid: self = .invalid
        case .link(let link): self = .link(link)
        }
    }
}

/// Hands a pairing request to the sheet in RootView. `onOpenURL` can fire before the environment
/// exists, so it posts to this process-wide instance instead (same pattern as `PlayerRouteRouter`).
@MainActor
@Observable
final class DevicePairingRouter {
    static let shared = DevicePairingRouter()

    private(set) var pending: DevicePairingRequest?

    func request(_ request: DevicePairingRequest) { pending = request }

    /// Read-and-clear: a request is delivered once.
    func take() -> DevicePairingRequest? {
        defer { pending = nil }
        return pending
    }
}
