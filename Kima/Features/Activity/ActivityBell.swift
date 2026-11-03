import SwiftUI

// A floating glass circle button that opens the Activity sheet.
// Badge: a small amber dot when anything is unread (no count; VoiceOver still reads it).

/// Small floating bell placed top-trailing in AppShellView's ZStack.
/// Tap calls `onOpen`; the shell owns the `showActivity` state.
struct ActivityBell: View {
    let onOpen: () -> Void

    /// How far the 44pt touch area reaches past the disc on each side; the shell's placement subtracts it so the
    /// disc itself sits on the page gutter.
    static let touchInset = (KimaLayout.minTouchTarget - KimaLayout.cornerDiscSize) / 2

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let unread = env.events.unreadCount
        Button(action: onOpen) {
            Image(systemName: unread > 0 ? "bell.fill" : "bell")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KimaColor.textPrimary)
                // Glass sits BEHIND the button and never takes touches: on iOS 26 a glassEffect on a
                // button's label becomes a UIKit view that swallows the tap (the button never fires).
                .kimaChromeDisc(size: KimaLayout.cornerDiscSize)
                // Badge is part of the button: centred 6pt in from the disc's top-trailing corner,
                // on its rim.
                .overlay(alignment: .topTrailing) {
                    if unread > 0 {
                        KimaCountBadge(count: unread, dotAbove: 0)
                            .alignmentGuide(.trailing) { $0[HorizontalAlignment.center] + 6 }
                            .alignmentGuide(.top) { $0[VerticalAlignment.center] - 6 }
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(Self.touchInset)
                .contentShape(Rectangle())
        }
        .buttonStyle(.kimaCard)
        .animation(.spring(duration: 0.3), value: unread)
        .accessibilityLabel(unread > 0 ? "activity, \(unread) unread" : "activity")
    }
}
