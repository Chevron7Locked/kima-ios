import SwiftUI

// MARK: - Root-hosted audit confirmation
// The false-starts audit's one-tap confirmation (collapse/remove), presented from AppShellView, NOT from StatsFalseStarts:
// a `.confirmationDialog`/`.sheet` presented inside a tab's NavigationStack renders but publishes ZERO accessibility
// elements. Root sheets are queryable. The collapse confirm states the consequence ("no play count changes") and offers two choices.

struct StatsConfirmSheet: View {
    let confirm: StatsConfirm
    /// The StatsFalseStarts-owned action (the POST + audit refresh live there;
    /// this view is UI only). Fires on the destructive button, sheet closes.
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xl) {
            Text(confirm.title)
                .font(KimaType.pageTitle)
                .foregroundStyle(KimaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: KimaSpacing.md) {
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text(confirm.destructiveLabel)
                        .kimaHitTarget()
                }
                .font(KimaType.headline)
                .foregroundStyle(confirm.kind == .remove ? KimaColor.danger : KimaColor.brand)
                .accessibilityIdentifier("stats-confirm-destructive")
                Spacer()
                Button { dismiss() } label: {
                    Text("cancel")
                        .kimaHitTarget()
                }
                .font(KimaType.headline)
                .foregroundStyle(KimaColor.textMuted)
                .accessibilityIdentifier("stats-confirm-cancel")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.xl)
        // Sheet chrome idiom: opaque surface, not kimaScreenCanvas (see StatsHourSheet —
        // the canvas backdrop is sized to the shell-window width, wider than any sheet;
        // the ambient wash bleeds past the sheet's own edges).
        .background(KimaColor.surface)
        .presentationDetents([.height(230)])
        .presentationBackground(KimaColor.surfaceRaised)
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("stats-confirm-sheet")
    }
}

/// A false-starts audit confirmation handed to the app root (dialogs presented from inside a tab publish no
/// AX elements). The closure is owned by the presenter, StatsFalseStarts, and fires on the destructive button;
/// it captures @State shared storage, so it sees the current picked-set/audit state when it runs.
struct StatsConfirm: Identifiable {
    enum Kind { case collapse, remove }
    let kind: Kind
    var count: Int = 0
    let id = UUID().uuidString
    let onConfirm: (Kind) -> Void
}

extension StatsConfirm {
    var title: String {
        switch kind {
        case .collapse: return "merge \(count.formatted(.number)) \(count == 1 ? "duplicate" : "duplicates")? play counts don't change"
        case .remove:   return "delete \(count.formatted(.number)) skipped \(count == 1 ? "play" : "plays")? this can't be undone"
        }
    }

    var destructiveLabel: String {
        switch kind {
        case .collapse: return "merge"
        case .remove:   return "delete"
        }
    }
}
