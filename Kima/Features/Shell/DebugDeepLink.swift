#if DEBUG
import Foundation

/// DEBUG-only screenshot tooling. Synthetic taps on the simulator are unreliable, so detail screens are
/// reached via a launch arg instead: `-kima-open <type>` pushes the first loaded item of that type once its
/// list has loaded. The matching tab root consumes it (AppShellView switches tab; the root's DEBUG `.task`
/// pushes). Not compiled into release.
enum DebugDeepLink {
    /// The `<type>` from a `-kima-open <type>` launch arg, else nil. Types: artist, album, audiobook, podcast,
    /// series (first audiobook series), audiobook-in-progress (first continue-listening book), browse-playlist
    /// (first featured playlist), queue and sleep-timer (player surfaces, fed through the same PlayerRoute queue
    /// as the kima:// URL scheme).
    static var requested: String? { launchArgValue("-kima-open") }

    /// The value following a `<flag>` launch arg, else nil (e.g.
    /// `-kima-whatsnew 2` → "2"). Shared by the launch-arg probes.
    static func launchArgValue(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.lastIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
#endif
