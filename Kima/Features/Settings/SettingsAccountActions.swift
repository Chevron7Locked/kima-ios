import SwiftUI

// The two account exits at the foot of Settings. Each is its own group: sign out first, then
// delete account alone at the very bottom, a full `huge` gap below sign out so the destructive
// row is never next to a routine one. Both are plain rows on the gutter, not cards or capsules.

// MARK: - Sign Out

struct SignOutSection: View {
    let onSignOut: () -> Void

    @State private var confirming = false

    var body: some View {
        Button { confirming = true } label: {
            HStack(spacing: KimaSpacing.md) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .medium))
                Text("sign out")
                    .font(KimaType.headline)
                Spacer(minLength: 0)
            }
            .foregroundStyle(KimaColor.textPrimary)
            .padding(.vertical, KimaSpacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.top, KimaSpacing.xxl)
        .confirmationDialog("sign out?", isPresented: $confirming, titleVisibility: .visible) {
            Button("sign out", role: .destructive, action: onSignOut)
            Button("cancel", role: .cancel) {}
        } message: {
            Text("you'll need to sign in again on this device.")
        }
    }
}

// MARK: - Danger Zone

struct DangerZoneSection: View {
    let isDeletingAccount: Bool
    let onDeleteAccount: () -> Void

    var body: some View {
        KimaDestructiveRow(
            label: "delete account",
            systemImage: "person.badge.minus",
            confirmTitle: "delete account",
            confirmMessage: "deletes your account and its data. this can't be undone.",
            confirmButton: "delete account",
            isBusy: isDeletingAccount,
            busyLabel: "deleting account…",
            action: onDeleteAccount
        )
    }
}
