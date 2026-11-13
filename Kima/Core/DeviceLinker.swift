import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum DeviceLinkResult: Equatable {
    case linked
    /// The caller cancelled; nothing was saved and there is nothing to show.
    case cancelled
    /// `message` is shown as-is. `canRetry` is true only when the same code can be sent again.
    case failed(message: String, canRetry: Bool)
}

/// The one place a pairing code becomes a signed-in device: send the code, then hand the API key
/// to `LoginRitual.establish` — the one ritual that stores it, drops every other stored login,
/// and remembers the server address. The typed-code path and the QR path both end here.
@MainActor
struct DeviceLinker {
    var makeClient: APIClientMaker = defaultAPIClientMaker
    var deviceName: () -> String = {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        "iPhone"
        #endif
    }

    /// The server may hold this request for about 45 s until the code's owner approves it; the client's
    /// default 60 s request timeout covers that. Cancelling the calling task hangs up, which frees the code.
    func link(code: String, server: KimaServer) async -> DeviceLinkResult {
        let response: DeviceLinkVerifyResponse
        do {
            let client = makeClient(server, nil)
            let name = deviceName()
            response = try await LinkKeepAlive.during {
                try await client.deviceLinkVerify(code: code, deviceName: name)
            }
        } catch {
            if Self.isCancellation(error) { return .cancelled }
            return Self.failure(for: error)
        }
        guard !Task.isCancelled else { return .cancelled }
        guard response.success, let apiKey = response.apiKey else {
            return .failed(message: Self.badCode, canRetry: false)
        }
        guard LoginRitual.establish(.apiKey(apiKey), at: server) else {
            return .failed(message: "couldn't securely save your device link. please try again.", canRetry: false)
        }
        return .linked
    }

    private static let badCode = "that code didn't work. get a new one and try again."

    static func failure(for error: Error) -> DeviceLinkResult {
        guard let api = error as? APIError else {
            return .failed(message: error.localizedDescription, canRetry: false)
        }
        guard case let .http(status, _) = api else {
            // A dropped connection while waiting leaves the code usable, so the same code can be sent again.
            var canRetry = false
            if case .network = api { canRetry = true }
            return .failed(message: api.errorDescription ?? "pairing failed.", canRetry: canRetry)
        }
        switch status {
        case 403: return .failed(message: "the link was denied.", canRetry: false)
        case 408: return .failed(message: "nobody approved it in time. try again.", canRetry: true)
        case 409: return .failed(message: "another device is already waiting on this code.", canRetry: true)
        case 404, 400: return .failed(message: badCode, canRetry: false)
        case 429: return .failed(message: "too many tries. wait a few minutes and try again.", canRetry: false)
        default: return .failed(message: api.errorDescription ?? "pairing failed.", canRetry: false)
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError { return true }
        if case let APIError.network(inner) = error {
            return (inner as? URLError)?.code == .cancelled || inner is CancellationError
        }
        return false
    }
}
