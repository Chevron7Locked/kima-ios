import SwiftUI

// MARK: - Environment re-injection for presented content

/// Content presented via `.sheet` / `.fullScreenCover` / `.popover` is hosted in a separate presentation host and does
/// not reliably inherit `@Observable` environment objects (`AppEnvironment`, `PlaybackController`, `ToastCenter`);
/// the first `@Environment(AppEnvironment.self)` read then traps (`EXC_BREAKPOINT`). Apply `.appEnvironment(env, toast)`
/// to the root of any presented view that reads them, passing the presenter's values. Over-applying is harmless.
extension View {
    func appEnvironment(_ env: AppEnvironment, _ toastCenter: ToastCenter) -> some View {
        self
            .environment(env)
            .environment(env.player)
            .environment(toastCenter)
            .environment(\.kimaChromeExtent, KimaChromeExtent())   // no tab bar or mini player over a sheet
            .environment(\.miniPlayerFootprint, 0)
    }
}
