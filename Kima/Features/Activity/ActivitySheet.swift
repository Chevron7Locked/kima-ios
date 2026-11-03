import SwiftUI

// Four-tab sheet: alerts · downloads · imports · history. Sections are in their own files.

// MARK: - Tab definition

enum ActivityTab: CaseIterable {
    case notifications, downloads, imports, history

    var label: String {
        switch self {
        case .notifications: "alerts"
        case .downloads:     "downloads"
        case .imports:       "imports"
        case .history:       "history"
        }
    }
}

// MARK: - ActivitySheet

/// App-level activity sheet. Presented as `.large` from AppShellView.
struct ActivitySheet: View {
    /// Called when the user taps a notification's view link; the shell routes it through `env.router`.
    let onDeepLink: (KimaNotification) -> Void

    @Environment(AppEnvironment.self) private var env

    /// Kept on the environment so the sheet reopens on the tab it was closed on.
    private var selectedTab: ActivityTab {
        get { env.activity.selectedTab }
        nonmutating set { env.activity.selectedTab = newValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            tabBar
            tabContent
        }
        .background(KimaColor.surfaceRaised.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KimaColor.surfaceRaised)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(alignment: .center, spacing: KimaSpacing.sm) {
            Text("activity")
                .font(KimaType.pageTitle)
                .foregroundStyle(KimaColor.textPrimary)
                .tracking(-0.4)
                .accessibilityIdentifier("activity-sheet-header")

            // Live updates connected (green) or not (muted).
            Circle()
                .fill(env.events.isConnected ? KimaColor.positive : KimaColor.textMuted)
                .frame(width: 6, height: 6)
                .accessibilityLabel(env.events.isConnected ? "live" : "not live")

            Spacer(minLength: 0)

            if env.events.unreadCount > 0 {
                KimaCountBadge(count: env.events.unreadCount)
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.top, KimaSpacing.lg)
    }

    // MARK: - Tabs

    private var tabBar: some View {
        KimaSegmented(
            options: ActivityTab.allCases.map { ($0, $0.label) },
            selection: Binding(get: { selectedTab }, set: { selectedTab = $0 })
        )
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.sm)
        .overlay(alignment: .bottom) {
            KimaHairline()
        }
    }

    // MARK: - Tab content
    //
    // All four sections stay mounted; only opacity and hit-testing change, so switching tabs never tears one down.
    // History and imports keep their lists on `env.activity`, so reopening shows them at once while they refresh.

    private var tabContent: some View {
        ZStack {
            NotificationsSection(onDeepLink: onDeepLink)
                .opacity(selectedTab == .notifications ? 1 : 0)
                .allowsHitTesting(selectedTab == .notifications)
            // Reuses the existing active-downloads UI (owns its own VM + polling).
            ActiveDownloadsView(embedded: true)
                .opacity(selectedTab == .downloads ? 1 : 0)
                .allowsHitTesting(selectedTab == .downloads)
            ImportsSection()
                .opacity(selectedTab == .imports ? 1 : 0)
                .allowsHitTesting(selectedTab == .imports)
            HistorySection()
                .opacity(selectedTab == .history ? 1 : 0)
                .allowsHitTesting(selectedTab == .history)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
