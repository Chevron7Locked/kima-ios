import SwiftUI

/// The failed downloads in the alerts list as one row ("18 downloads failed"); tapping it shows each album and why.
struct NotificationFailureGroup: View {
    let failures: [KimaNotification]
    let onDeepLink: (KimaNotification) -> Void

    @State private var expanded = false

    private var hasUnread: Bool { failures.contains { !$0.read } }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: KimaSpacing.md) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(KimaColor.danger)
                        .frame(width: 16, height: 16)
                        .padding(.top, 2)  // optical: sits the icon on the first text line
                    VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                        Text("\(failures.count) downloads failed")
                            .font(KimaType.captionStrong)
                            .foregroundStyle(hasUnread ? KimaColor.textPrimary : KimaColor.textMuted)
                        Text("latest \(Formatters.relativeTimeString(fromISO8601: failures.first?.createdAt ?? ""))")
                            .font(KimaType.meta.monospacedDigit())
                            .foregroundStyle(KimaColor.textMuted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(KimaColor.textMuted)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .frame(height: 20)
                }
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.vertical, KimaSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(hasUnread ? KimaColor.surface.opacity(0.6) : Color.clear)
            .overlay(alignment: .bottom) { KimaHairline() }
            .accessibilityLabel("\(failures.count) downloads failed")
            .accessibilityHint(expanded ? "hides the albums" : "shows each album and why")

            if expanded {
                ForEach(failures) { n in
                    NotificationRow(notification: n, inGroup: true, onDeepLink: onDeepLink)
                }
            }
        }
    }
}
