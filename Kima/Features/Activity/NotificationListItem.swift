import Foundation

/// A server download-failure message, "Failed to download <artist> - <album>: <reason>", split into the album line and
/// the reason, both lowercased. Nil when the message has another shape.
struct DownloadFailureText: Equatable {
    let subject: String
    let reason: String

    init?(message: String?) {
        let prefix = "failed to download "
        guard let lower = message?.lowercased(), lower.hasPrefix(prefix) else { return nil }
        let rest = lower.dropFirst(prefix.count)
        if let colon = rest.range(of: ": ") {
            subject = rest[..<colon.lowerBound].trimmingCharacters(in: .whitespaces)
            reason = rest[colon.upperBound...].trimmingCharacters(in: .whitespaces)
        } else {
            subject = rest.trimmingCharacters(in: .whitespaces)
            reason = ""
        }
        if subject.isEmpty { return nil }
    }
}

/// One row of the alerts list: a notification on its own, or every failed download together once there is more than
/// one (placed where the newest failure was).
enum NotificationListItem: Identifiable {
    case single(KimaNotification)
    case failures([KimaNotification])

    static let failureType = "download_failed"

    var id: String {
        switch self {
        case .single(let n):   n.id
        case .failures:        "failures"
        }
    }

    static func items(from notifications: [KimaNotification]) -> [NotificationListItem] {
        let failed = notifications.filter { $0.type == failureType }
        guard failed.count > 1 else { return notifications.map(NotificationListItem.single) }
        var items: [NotificationListItem] = []
        for n in notifications {
            if n.type != failureType {
                items.append(.single(n))
            } else if n.id == failed.first?.id {
                items.append(.failures(failed))
            }
        }
        return items
    }
}
