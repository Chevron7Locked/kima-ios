import SwiftUI

// The what's-new release-window mount: the binding, the session load, and the navigation
// target. The sheet itself is mounted in AppShellView's body (`.sheet(item: whatsNewCurrent)`).

extension AppShellView {

    /// Binding driving the release-window sheet. Only the getter matters —
    /// WhatsNewSheetView disables interactive dismissal (closing is a real,
    /// server-recorded answer), so the setter path fires on nothing; the nil
    /// write just maps back to closeCurrent for symmetry.
    var whatsNewCurrent: Binding<WhatsNewRelease?> {
        Binding(
            get: { env.whatsNew.current },
            set: { if $0 == nil { env.whatsNew.closeCurrent() } }
        )
    }

    /// First authed shell appearance (and every re-mount after: loadOnce
    /// caches per session/token).
    func whatsNewGateLoad() async {
        await env.acquire.refresh(client: env.client)
        await env.whatsNew.loadOnce()
        #if DEBUG
        // Launch probe: -kima-whatsnew <n> REPLACES the queue with a synthetic
        // window queue so the full UI can be swept deterministically on any
        // server (runs after loadOnce — see WhatsNewGateModel.debugInject for
        // why replacement beats queue.isEmpty).
        if let arg = DebugDeepLink.launchArgValue("-kima-whatsnew"),
           let n = Int(arg), n > 0 {
            env.whatsNew.debugInject(WhatsNewRelease.debugSample(n: n))
        }
        #endif
    }

    /// "Take me to it" from a what's-new window. /stats targets switch to the More tab and ask it to present Stats,
    /// scrolling to the false-starts audit when the path carries #false-starts. /vibe opens the app-root vibe map —
    /// the 1.11 note's links point there.
    func deliverWhatsNewTarget(path: String) {
        if path.hasPrefix("/stats") {
            // The web window's target is /stats#false-starts — route to the
            // More tab (stats lives there) and let it present on arrival.
            env.router.selectedTab = .more
            env.router.statsRequest = true
            env.router.statsScrollToAudit = path.contains("#false-starts")
        } else if path.hasPrefix("/vibe") {
            // The window is dismissing in this same turn (its go-to defers the rest
            // and posts the dismissal), and the map is the shell's one full-screen
            // cover: presenting in the same transaction as a sheet's dismissal is how
            // a presentation gets dropped. Next turn, after the sheet has begun to go.
            DispatchQueue.main.async { [env] in
                env.router.showVibeMap = true
            }
        }
    }
}
