import SwiftUI

// MARK: - SleepTimerButton

/// Compact trigger that lives in the secondary controls row.
/// Delegates to `PlayerSecondaryButton` for the icon/label/on-when-active layout.
/// While active, the label shows a live countdown badge ("30m", "1:45") instead of "sleep".
/// Tapping opens `SleepTimerSheet`.
struct SleepTimerButton: View {

    let model: SleepTimerModel
    @Environment(AppEnvironment.self) private var env
    @State private var showSheet = false

    /// Deep-link path binding (the model's own flag — the same binding FullPlayerView
    /// attaches). A model-owned sheet flag cannot be `$`-projected from a plain `let`.
    private var deepLinkSheet: Binding<Bool> {
        Binding(get: { model.showSheet }, set: { model.showSheet = $0 })
    }

    var body: some View {
        PlayerSecondaryButton(
            icon: "timer",
            label: model.isActive
                ? model.displayRemaining
                : (model.endPolicyActive ? "after \(model.endPolicyLabel)" : "sleep"),
            active: model.isActive || model.endPolicyActive
        ) { showSheet = true }
        // Override the generic accessibilityLabel with a more descriptive sleep-specific one.
        .accessibilityLabel(
            model.isActive
                ? "sleep timer active: \(model.displayRemaining) remaining"
                : (model.endPolicyActive
                    ? "sleep timer: end of \(model.endPolicyLabel)"
                    : "set sleep timer")
        )
        .sheet(isPresented: $showSheet) { sheetContent }
        .accessibilityIdentifier("sleep-timer-button")
        // Deep-link / programmatic open (kima://sleep-timer → player.sleepTimer.showSheet).
        // set() auto-dismisses, so the sheet only lingers when nothing was armed.
        .sheet(isPresented: deepLinkSheet) { sheetContent }
    }

    private var sheetContent: some View {
        SleepTimerSheet(onColour: env.accent.color, model: model)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(KimaColor.surfaceRaised)
    }
}
