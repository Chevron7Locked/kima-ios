#if DEBUG
import Foundation

/// DEBUG-only simulator of the vibe-map 202 "computing" answer, to test the poll path without a fresh-compute server.
/// `-kima-vibe-computing <N>` makes the first N map fetches answer `.computing`, then the real answer flows.
/// `-kima-vibe-fail <status>` makes the fetch fail with that HTTP status instead. No-op without the launch arg.
enum DebugVibeComputingSimulator {
    private static let wanted: Int? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-kima-vibe-computing"),
              i + 1 < args.count, let n = Int(args[i + 1]) else { return nil }
        return n
    }()

    /// Fetches served as fake "computing" answers so far. Actor state — getVibeMap
    /// runs on the API-client actor; actor isolation keeps the counter race-free.
    nonisolated(unsafe) private static var seen = 0

    /// `-kima-vibe-fail <status>`: every map fetch throws `APIError.http(status, …)`.
    static let failStatus: Int? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-kima-vibe-fail"),
              i + 1 < args.count, let n = Int(args[i + 1]) else { return nil }
        return n
    }()

    static func shouldSimulateComputing() async -> Bool {
        guard let wanted, seen < wanted else { return false }
        seen += 1
        return true
    }
}
#endif
