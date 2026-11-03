import Foundation
import Observation

/// What the activity sheet keeps between opens: the selected tab, the history and import lists,
/// and whether their last load failed. Lives on `AppEnvironment` because the sheet's views are
/// rebuilt every time it opens.
@MainActor
@Observable
final class ActivityStore {
    var selectedTab: ActivityTab = .notifications
    var history: [DownloadHistoryItem] = []
    var historyFailed = false
    var imports: [ImportJob] = []
    var importsFailed = false
}
