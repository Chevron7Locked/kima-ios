import SwiftUI

// Reads env.events.notifications (SSEManager, @Observable). All mutations go through
// SSEManager — optimistic local updates with async server sync.

/// Notifications tab body. Loaded and retained by ActivitySheet.
struct NotificationsSection: View {
    let onDeepLink: (KimaNotification) -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            if !env.events.notifications.isEmpty {
                headerBar
            }
            if env.events.notifications.isEmpty {
                emptyState
            } else {
                notificationList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Refresh once on appear; SSEManager keeps the list live via SSE events.
        .task { await env.events.refreshNotifications() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text(String(format: "%d item%@",
                        env.events.notifications.count,
                        env.events.notifications.count == 1 ? "" : "s"))
                .font(KimaType.meta.monospacedDigit())
                .foregroundStyle(KimaColor.textMuted)
            Spacer(minLength: 0)
            // "clear all" is destructive, so it lives at the end of the list, not up here.
            if env.events.notifications.contains(where: { !$0.read }) {
                Button {
                    Task { await env.events.markAllRead() }
                } label: {
                    Text("mark all read")
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, KimaSpacing.lg)
        .overlay(alignment: .bottom) {
            KimaHairline()
        }
    }

    // MARK: - List

    private var notificationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(NotificationListItem.items(from: env.events.notifications)) { item in
                    switch item {
                    case .single(let n):
                        NotificationRow(notification: n, onDeepLink: onDeepLink)
                    case .failures(let failed):
                        NotificationFailureGroup(failures: failed, onDeepLink: onDeepLink)
                    }
                }
                KimaDestructiveRow(
                    label: "clear all",
                    confirmTitle: "clear all notifications?",
                    confirmButton: "clear all"
                ) {
                    Task { await env.events.clearAll() }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        KimaEmptyState(icon: "bell", title: "no notifications", message: nil)
    }
}

// MARK: - Notification row

/// One alert. Inside the failed-downloads group (`inGroup`) it drops the repeated icon and title and shows the album
/// and the reason instead.
struct NotificationRow: View {
    let notification: KimaNotification
    var inGroup = false
    let onDeepLink: (KimaNotification) -> Void

    private var failure: DownloadFailureText? { DownloadFailureText(message: notification.message) }

    private var titleText: String {
        if inGroup, let failure { return failure.subject }
        return notification.title.lowercased()
    }

    private var messageText: String? {
        guard let failure else { return notification.message }
        if inGroup { return failure.reason.isEmpty ? nil : failure.reason }
        return failure.reason.isEmpty ? failure.subject : "\(failure.subject): \(failure.reason)"
    }

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(alignment: .top, spacing: KimaSpacing.md) {
            // Type icon (in the failure group the group row carries it)
            Image(systemName: typeIcon)
                .font(.system(size: 13))
                .foregroundStyle(typeColor)
                .frame(width: 16, height: 16)
                .padding(.top, 2)  // optical: sits the icon on the first text line
                .opacity(inGroup ? 0 : 1)

            // Content
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(titleText)
                    .font(KimaType.captionStrong)
                    .foregroundStyle(notification.read ? KimaColor.textMuted : KimaColor.textPrimary)
                    .lineLimit(2)

                if let msg = messageText {
                    Text(msg)
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)
                        .lineLimit(2)
                }

                HStack(spacing: KimaSpacing.sm) {
                    Text(relativeTime)
                        .font(KimaType.meta.monospacedDigit())
                        .foregroundStyle(KimaColor.textMuted)

                    if hasDeepLink {
                        Text("•").font(KimaType.meta).foregroundStyle(KimaColor.textMuted)
                        Button {
                            Task { await env.events.markRead(id: notification.id) }
                            onDeepLink(notification)
                        } label: {
                            Text("view")
                                .font(KimaType.meta)
                                .foregroundStyle(KimaColor.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)

            // Row actions
            HStack(spacing: KimaSpacing.sm) {
                if !notification.read {
                    ActivityRowActionButton(
                        systemImage: "checkmark",
                        accessibilityLabel: "mark read"
                    ) {
                        Task { await env.events.markRead(id: notification.id) }
                    }
                }
                ActivityRowActionButton(
                    systemImage: "xmark",
                    accessibilityLabel: "dismiss"
                ) {
                    Task { await env.events.clear(id: notification.id) }
                }
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.md)
        // Unread: subtle surface tint + brighter title only, no side-stripe.
        .background(notification.read ? Color.clear : KimaColor.surface.opacity(0.6))
        .overlay(alignment: .bottom) {
            KimaHairline()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !notification.read else { return }
            Task { await env.events.markRead(id: notification.id) }
        }
    }

    // MARK: Helpers

    private var typeIcon: String {
        switch notification.type {
        case "download_complete":               return "checkmark.circle.fill"
        case "download_failed":                 return "exclamationmark.circle.fill"
        case "playlist_ready", "import_complete": return "music.note.list"
        default:                                return "bell.fill"
        }
    }

    private var typeColor: Color {
        switch notification.type {
        case "download_complete":               return KimaColor.positive
        case "download_failed":                 return KimaColor.danger
        case "playlist_ready", "import_complete": return KimaColor.positive
        default:                                return KimaColor.textMuted
        }
    }

    private var hasDeepLink: Bool {
        notification.metadata?.playlistId != nil
        || notification.metadata?.albumId   != nil
        || notification.metadata?.artistId  != nil
    }

    private var relativeTime: String {
        Formatters.relativeTimeString(fromISO8601: notification.createdAt)
    }
}
