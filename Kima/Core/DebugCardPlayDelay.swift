#if DEBUG
import Foundation

/// DEBUG-only latency for the card play fetches (an artist's or album's detail call before playback),
/// so the badge's in-flight spinner lasts long enough for a UI test to see it.
/// `-kima-card-play-delay <ms>`; no-op without the launch arg.
enum DebugCardPlayDelay {
    static let millis: Int? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-kima-card-play-delay"),
              i + 1 < args.count, let n = Int(args[i + 1]) else { return nil }
        return n
    }()

    static func apply() async {
        guard let millis else { return }
        try? await Task.sleep(for: .milliseconds(millis))
    }
}

/// DEBUG-only suppression of the whats-new gate: `-kima-no-whatsnew`. The gate is server-decided
/// (GET /whats-new/pending records nothing locally), so a release pending for the signed-in account
/// covers every UI suite's screen with a full-screen sheet. Suppressing it here leaves the app, the
/// API and the server-side record untouched — no account marks its release window seen.
enum DebugNoWhatsNew {
    static let enabled: Bool = CommandLine.arguments.contains("-kima-no-whatsnew")
}
#endif
