import SwiftUI
import UIKit

extension AppShellView {
    /// Notification, playback and accent observers applied to the shell root.
    func withObservers<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: env.playerRoute.pending) { _, _ in deliverPlayerRoute() }
        // A route left pending because the player was idle delivers the moment a
        // session exists — hydration after launch, or the user pressing play.
        .onChange(of: env.player.isActive) { _, active in
            if active { deliverPlayerRoute() }
        }
        // SSE auth failure (401/403 that a refresh couldn't fix): the reconnect loop has stopped.
        // Surface it so live updates dying isn't silent; the next API 401 drives full re-auth.
        .onReceive(NotificationCenter.default.publisher(for: .kimaSSEAuthFailed)) { _ in
            toastCenter.show("session expired. sign in again.", style: .error)
        }
        // Keyboard show/hide → hide the floating mini-player (see `keyboardUp`). These fire once
        // each, so `keyboardUp` flips a single time per transition — no per-frame churn.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
        .task { await whatsNewGateLoad() }
        // Sync swipe state with playback — reset on track change, restore on resume.
        .onChange(of: player.currentTrack?.id) { _, id in
            swipeState.sync(trackId: id, isPlaying: player.isPlaying)
        }
        .onChange(of: player.isPlaying) { _, playing in
            swipeState.sync(trackId: player.currentTrack?.id, isPlaying: playing)
        }
        // A play request always shows the bar. `sync` keys on the track id, so replaying the
        // track that is already current — tapping "your top 20" while its first track is loaded —
        // leaves a minimized bar minimized: audio restarts and the screen shows nothing.
        .onChange(of: player.playRequestCount) { _, _ in
            swipeState.showBar()
        }
        // Player-originated notices (e.g. a gone track was skipped) → toast, then clear.
        .onChange(of: player.playerNotice) { _, notice in
            guard let notice else { return }
            toastCenter.show(notice)
            player.playerNotice = nil
        }
        // Adaptive accent — seed on first appearance (no animation; we don't know the track yet).
        .task { env.refreshAccent(from: player.currentTrack) }
        // Crossfade accent on track change.
        .onChange(of: player.currentTrack?.id) { _, _ in
            withAnimation(.easeInOut(duration: 0.6)) { env.refreshAccent(from: player.currentTrack) }
        }
        // Re-derive accent when the map (the only colour source) loads or changes.
        .onChange(of: env.vibeMapViewModel.mapKey) { _, _ in
            withAnimation(.easeInOut(duration: 0.6)) { env.refreshAccent(from: player.currentTrack) }
        }
        .task {
            if case .loading = env.vibeMapViewModel.phase {
                await env.vibeMapViewModel.load(client: env.client)
            }
        }
        // Ambient field — resolve the cover-art palette on appear and on every track change. task(id:) cancels the
        // previous resolve, so a slow lookup for an earlier track never lands last. Long-form has no cover id → nil.
        .task(id: player.currentTrack?.id) {
            let resolved = await CoverArtColor.palette(coverId: player.currentTrack?.album?.coverArt, server: env.server)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { env.ambientPalette = resolved }
        }
    }
}
