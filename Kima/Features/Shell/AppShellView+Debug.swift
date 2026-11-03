#if DEBUG
import SwiftUI

extension AppShellView {
    /// DEBUG launch hooks, run from the shell body's `.task` (launch args used by KimaUITests).
    func debugLaunchHooks() async {
        let args = CommandLine.arguments
        Task.detached(priority: .utility) { await DebugLogDump.run() }
        if let i = args.firstIndex(of: "-kima-tab"), i + 1 < args.count,
           let tab = Int(args[i + 1]).flatMap(AppTab.init(rawValue:)) {
            env.router.selectedTab = tab
        }
        // UI-test hook: show an unread badge on the bell without a server.
        if let i = args.firstIndex(of: "-kima-fake-unread"), i + 1 < args.count, let n = Int(args[i + 1]) {
            env.events.unreadCount = n
        }
        // Screenshot hook: put a placeholder track in the queue so the mini player shows, with no
        // audio loaded and no server call (the engine is never started).
        if args.contains("-kima-fake-now-playing"),
           let data = #"{"id":"fake-track","title":"placeholder track","duration":200,"artist":{"id":"a","name":"placeholder artist"},"album":{"id":"b","title":"placeholder album","coverArt":null}}"#.data(using: .utf8),
           let track = try? JSONDecoder().decode(Track.self, from: data) {
            // Inserted at once, like a fast server restore, so shots exercise the launch path.
            player.queue = [track]
            player.currentIndex = 0
        }
        // UI-test hook: placeholder tracks queued (six, or the count after the flag) with the first current, nothing
        // loaded and nothing saved to the server, so reordering in the queue sheet can be tested on its own.
        if args.contains("-kima-fake-queue") {
            let count = DebugDeepLink.launchArgValue("-kima-fake-queue").flatMap(Int.init) ?? 6
            player.syncHook = nil
            player.queue = (1...max(1, count)).compactMap { n in
                #"{"id":"fake-\#(n)","title":"queued \#(n)","duration":200,"artist":{"id":"a","name":"placeholder artist"}}"#
                    .data(using: .utf8).flatMap { try? JSONDecoder().decode(Track.self, from: $0) }
            }
            player.currentIndex = 0
        }
        // UI-test hooks: a fake song-path queue, then ask to replace it with a play-similar queue. Agreeing
        // flips the queue to "play similar"; cancelling leaves "song path". Plain: asked over the full
        // player. -shell: asked over the shell. -handoff: asked over the shell, then the player opens.
        let replaceHooks = ["-kima-vibe-fake-replace", "-kima-vibe-fake-replace-shell", "-kima-vibe-fake-replace-handoff"]
        if let hook = replaceHooks.first(where: args.contains) {
            player.queueOrigin = .songPath
            if hook == replaceHooks[0] { showFullPlayer = true }
            let player = player
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                if await player.confirmVibeReplace(with: .playSimilar) { player.queueOrigin = .playSimilar }
            }
            if hook == replaceHooks[2] {
                Task {
                    try? await Task.sleep(for: .milliseconds(4000))
                    showFullPlayer = true
                }
            }
        }
        // UI-test hook: after n seconds, ask for stats from outside More, as the full player's stats
        // button does.
        if let i = args.firstIndex(of: "-kima-stats-request-after"), i + 1 < args.count, let s = Double(args[i + 1]) {
            let router = env.router
            Task {
                try? await Task.sleep(for: .seconds(s))
                router.selectedTab = .more
                router.statsRequest = true
            }
        }
        // Screenshot hook: a toast with an undo button, as reset progress or hiding a playlist shows. Its
        // undo only toasts; nothing reaches the server.
        if args.contains("-kima-fake-undo-toast") {
            let toast = toastCenter
            Task {
                try? await Task.sleep(for: .seconds(3))
                toast.show("progress reset", style: .success,
                           action: ToastAction(label: "undo") { toast.show("progress put back", style: .success) })
            }
        }
        // Screenshot hook: ask for landscape once the scene is active, so iPad layouts can be shot both ways without
        // Simulator.app. The answer is logged ("kima-landscape: …"): iPadOS 26 refuses it while the app takes part in
        // its windowing modes, and the window then stays as the device holds it.
        if args.contains("-kima-landscape") {
            Task {
                for _ in 0 ..< 40 {
                    if let scene = UIApplication.shared.connectedScenes
                        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
                            NSLog("kima-landscape: %@", error.localizedDescription)
                        }
                        NSLog("kima-landscape: requested")
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                NSLog("kima-landscape: no active scene")
            }
        }
        if args.contains("-kima-open-player") {
            try? await Task.sleep(for: .milliseconds(700))
            showFullPlayer = true
        }
        // Screenshot deep-link: switch to the tab that hosts the requested detail type; the
        // root's own DEBUG task pushes the first loaded item (see DebugDeepLink).
        switch DebugDeepLink.requested {
        case "artist", "album":  env.router.selectedTab = .library
        case "audiobook", "audiobook-in-progress", "series": env.router.selectedTab = .audiobooks
        case "browse-playlist":  env.router.selectedTab = .home
        case "podcast", "podcast-chart", "podcast-preview": env.router.selectedTab = .podcasts
        case "settings", "search": env.router.selectedTab = .more
        case "designlab", "licenses", "changelog", "discover": env.router.selectedTab = .more
        case "stats": env.router.selectedTab = .more
        case "vibe":               env.router.showVibeMap = true
        case "activity":           showActivity = true
        case "report":             env.router.showIssueReporter = true
        case "playlist", "playlists": env.router.selectedTab = .more
        case "queue", "sleep-timer":
            // Test hook: feed the SAME route queue the URL scheme uses.
            PlayerRouteRouter.shared.request(DebugDeepLink.requested == "queue" ? .queue : .sleepTimer)
        default:                 break
        }
        deliverPlayerRoute()   // consume a route latched by launch arg (DEBUG)
    }
}
#endif
