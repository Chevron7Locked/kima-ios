import Foundation

// MARK: - Play reporting (POST /plays)
// No UI, never throws. The server decides what counts as a play; iOS only reports seconds.
// The caller retries a report that didn't get through once (`PlaybackController.sendPlayReport`).

/// Server verdict on a reported listen: recorded, plus why-not when it wasn't.
/// Read for DEBUG logging only — never gates UI. Mirrors the `PlayOutcome` union
/// (unknown-track arrives as a 404 and lands in the catch, same as web).
struct PlayOutcome: Decodable {
    let recorded: Bool
    let playId: String?
    let reason: String?   // "too-short" | "not-enough-listened" | "duplicate"
}

private struct PlayReportBody: Encodable {
    let trackId: String
    let secondsListened: Int
}

extension KimaAPIClient {

    /// POST /plays. `secondsListened` is the meter's capped-delta measurement, rounded.
    /// True when the server answered, whatever it decided (a 4xx answer won't change on a retry);
    /// false when the report didn't get through (no connection, a server error) and is worth one more try.
    @discardableResult
    func reportPlay(trackId: String, secondsListened: Double) async -> Bool {
        // Clamp before rounding: Int(...) traps on absurd values; the server caps
        // at 86400 anyway.
        let seconds = Int(min(max(secondsListened, 0), 86_400).rounded())
        let body = PlayReportBody(trackId: trackId, secondsListened: seconds)
        do {
            let outcome: PlayOutcome = try await postJSON("/plays", body: body, authed: true)
            #if DEBUG
            // Server-authoritative verdict, log-only (plan T4): lets a live probe confirm
            // the meter → POST → Play-row path from `log show` without any UI coupling.
            print("[PlayReport] recorded=\(outcome.recorded) reason=\(outcome.reason ?? "-") "
                + "track=\(trackId) sec=\(seconds)")
            #endif
            return true
        } catch {
            #if DEBUG
            print("[PlayReport] failed \(error) track=\(trackId) sec=\(seconds)")
            #endif
            switch error {
            case APIError.network:                                   return false
            case APIError.http(let status, _) where status >= 500:  return false
            default:                                                 return true
            }
        }
    }
}
