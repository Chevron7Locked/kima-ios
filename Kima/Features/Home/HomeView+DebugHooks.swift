#if DEBUG
import SwiftUI

// MARK: - HomeDebugHooks

/// Screenshot and repro launch-argument hooks for the Home tab (mixer auto-present, vibe
/// auto-present, deep-link player). Not compiled into release. Bindings keep HomeView's
/// `@State` private.
struct HomeDebugHooks: ViewModifier {
    @Binding var showMixerDebug: Bool
    @Binding var showVibeMap: Bool
    @Binding var showRadio: Bool
    @Binding var showReleasesRadar: Bool
    @Binding var path: [LibraryRoute]
    let vm: HomeViewModel

    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    func body(content: Content) -> some View {
        content
        .task {
            guard CommandLine.arguments.contains("-kima-open-mixer") else { return }
            try? await Task.sleep(for: .milliseconds(1500))
            showMixerDebug = true
        }
        .sheet(isPresented: $showMixerDebug) {
            MoodMixerView(onMixesReload: { await vm.reloadMixes(using: env.client) })
                .appEnvironment(env, toast)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .task {
            if CommandLine.arguments.contains("-kima-open-vibe") {
                try? await Task.sleep(for: .milliseconds(900))
                showVibeMap = true
                return
            }
            switch DebugDeepLink.requested {
            case "radio":    showRadio = true
            case "releases": showReleasesRadar = true
            case "browse-playlist":
                // Pushes the first featured playlist once Home has loaded.
                for _ in 0..<50 {
                    if let first = vm.featuredPlaylists.first { path.append(.browsePlaylistDetail(id: first.id)); return }
                    try? await Task.sleep(for: .milliseconds(120))
                }
            case "play-first":
                // Feed the player the first library track — play reporting probes
                // (POST /plays) need a playing music queue, and synthetic taps are
                // unreliable (same rationale as every hook above). Combine with
                // `-kima-open-player` (AppShellView) to auto-present the full player.
                if let first = try? await env.client.getLibraryTracks(limit: 1).tracks.first {
                    env.player.play(tracks: [first], startAt: 0)
                }
            case "skip-missing":
                // Repro hook: a bare shuffle track, then an unplayable id in front of a fresh copy
                // of it (PlaybackController.debugPlayMissingThenReal). The toast marks round 2.
                if let real = try? await env.client.getShuffledTracks(limit: 1).first {
                    await env.player.debugPlayMissingThenReal(real)
                    toast.show("debug: skip-missing round 2")
                }
            case "skip-gone":
                // Repro hook: three unplayable ids in front of a real track
                // (PlaybackController.debugPlayThreeMissingThenReal).
                if let real = try? await env.client.getShuffledTracks(limit: 1).first {
                    env.player.debugPlayThreeMissingThenReal(real)
                }
            default: break
            }
        }
    }
}
#endif
