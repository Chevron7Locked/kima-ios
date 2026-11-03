import SwiftUI

extension AppShellView {
    /// App-level sheets, applied to the shell root.
    func withSheets<Content: View>(_ content: Content) -> some View {
        content
        // Player deep-link surfaces (kima://queue · kima://sleep-timer) — presented here
        // when the full player is NOT up; deliverPlayerRoute keeps both paths exclusive.
        .queueSheet(isPresented: $showQueueRouteSheet, env: env, toastCenter: toastCenter)
        .sleepTimerRouteSheet(isPresented: $showSleepRouteSheet, model: env.player.sleepTimer, onColour: env.accent.color)
        // The stats listening-clock hour drill. Presented HERE, not by
        // StatsView: a sheet inside a tab's NavigationStack renders dark and
        // publishes zero accessibility elements (probe: sheets=0, done button
        // absent); root sheets are fully queryable (queue/sleep/whats-new).
        .sheet(item: Binding(get: { env.router.hourDrill }, set: { env.router.hourDrill = $0 })) { drill in
            StatsHourSheet(weekday: drill.dow, hour: drill.hour, period: drill.period)
                .appEnvironment(env, toastCenter)
        }
        .sheet(item: Binding(get: { env.router.statsConfirm }, set: { env.router.statsConfirm = $0 })) { confirm in
            StatsConfirmSheet(confirm: confirm) { confirm.onConfirm(confirm.kind) }
                .appEnvironment(env, toastCenter)
        }
        // Activity sheet — app-level, above the tab structure.
        .sheet(isPresented: $showActivity) {
            ActivitySheet(onDeepLink: { note in
                showActivity = false           // dismiss so the pushed detail is visible
                env.router.open(note)
            })
            .appEnvironment(env, toastCenter)
        }
        // Quick issue-report sheet, opened from the More tab. App-level, above the tab structure, so it
        // publishes accessibility elements. Captures now-playing + screen context on appear.
        .sheet(isPresented: Binding(get: { env.router.showIssueReporter }, set: { env.router.showIssueReporter = $0 })) {
            IssueReportSheet()
                .appEnvironment(env, toastCenter)
        }
        // Add-to-Playlist sheet — app-level; driven by env.playlistPicker.source.
        // Dismissal (swipe or in-sheet action) sets source back to nil.
        .sheet(item: playlistPickerSource) { source in
            PlaylistPickerSheet(source: source)
                .appEnvironment(env, toastCenter)
        }
        // What's-new release window — app-level gate (web parity: AuthenticatedLayout
        // mounts WhatsNewGate). Queue + server-side dismissals live in env.whatsNew.
        // Blockers close by button only — swipe-to-close is a non-answer by design.
        .sheet(item: whatsNewCurrent) { release in
            WhatsNewSheetView(
                release: release,
                onClose: { env.whatsNew.closeCurrent() },
                onGoToTarget: { deliverWhatsNewTarget(path: $0) }
            )
            .presentationDetents([.large])
            .appEnvironment(env, toastCenter)
        }
    }

    /// Binding to the app-wide Add-to-Playlist source, for `.sheet(item:)`. Reading/writing
    /// goes through the observable `PlaylistPickerModel` so any surface can drive presentation.
    private var playlistPickerSource: Binding<PlaylistAddSource?> {
        Binding(
            get: { env.playlistPicker.source },
            set: { env.playlistPicker.source = $0 }
        )
    }
}
