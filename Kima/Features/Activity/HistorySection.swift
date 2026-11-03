import SwiftUI

// Endpoints under /api/notifications/downloads:
// history (last 50, deduped by subject), :id/clear, clear-all, :id/retry.

/// History tab body. Failed jobs shown first, then completed.
struct HistorySection: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    @State private var isLoading = false
    @State private var retryingIds: Set<String> = []

    var body: some View {
        content
            .task { await env.acquire.refresh(client: env.client) }
    }

    private var content: some View {
        ZStack {
            if isLoading && history.isEmpty {
                loadingState
            } else if env.activity.historyFailed && history.isEmpty {
                KimaErrorState(message: "couldn't load download history") { Task { await fetchHistory() } }
            } else if history.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Runs on appear and on every download SSE tick; a newer tick cancels the older fetch.
        .task(id: env.events.downloadTick) { await fetchHistory() }
    }

    // MARK: - Fetch

    /// Kept on `env.activity` so the list survives the sheet closing.
    private var history: [DownloadHistoryItem] {
        get { env.activity.history }
        nonmutating set { env.activity.history = newValue }
    }

    private func fetchHistory() async {
        if history.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            history = try await env.client.getDownloadHistory()
            env.activity.historyFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            env.activity.historyFailed = true
        }
    }

    // MARK: - States

    private var loadingState: some View {
        KimaLoadingState(text: "loading history…") { Task { await fetchHistory() } }
    }

    private var emptyState: some View {
        KimaEmptyState(icon: "clock", title: "no download history", message: "completed downloads show up here")
    }

    // MARK: - List

    private var historyList: some View {
        let failed    = history.filter { $0.status == "failed" || $0.status == "exhausted" }
        let completed = history.filter { $0.status == "completed" }
        return VStack(spacing: 0) {
            historyHeader(failed: failed.count, completed: completed.count)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !failed.isEmpty {
                        sectionBanner(label: String(format: "failed (%d)", failed.count),
                                      color: KimaColor.danger)
                        ForEach(failed) { item in
                            HistoryRow(item: item,
                                       isRetrying: retryingIds.contains(item.id),
                                       onRetry: env.acquire.canAcquire ? { Task { await retry(id: item.id) } } : nil,
                                       onClear: { Task { await clearItem(id: item.id) } })
                        }
                    }
                    if !completed.isEmpty {
                        sectionBanner(label: String(format: "completed (%d)", completed.count),
                                      color: KimaColor.textSecondary)
                        ForEach(completed) { item in
                            HistoryRow(item: item,
                                       isRetrying: false, onRetry: nil,
                                       onClear: { Task { await clearItem(id: item.id) } })
                        }
                    }
                    KimaDestructiveRow(
                        label: "clear all",
                        confirmTitle: "clear all download history?",
                        confirmButton: "clear all"
                    ) {
                        Task { await clearAll() }
                    }
                    Spacer(minLength: KimaSpacing.huge)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func historyHeader(failed: Int, completed: Int) -> some View {
        HStack(spacing: KimaSpacing.md) {
            if completed > 0 {
                Label {
                    Text(String(format: "%d", completed)).foregroundStyle(KimaColor.textSecondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(KimaColor.positive)
                }
                .font(KimaType.meta.monospacedDigit())
                .labelStyle(.titleAndIcon)
            }
            if failed > 0 {
                Label(String(format: "%d", failed), systemImage: "xmark.circle.fill")
                    .font(KimaType.meta.monospacedDigit())
                    .foregroundStyle(KimaColor.danger)
                    .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
            // "clear all" is destructive, so it lives at the end of the list, not up here.
        }
        .frame(minHeight: 44)
        .padding(.horizontal, KimaSpacing.lg)
        .overlay(alignment: .bottom) {
            KimaHairline()
        }
    }

    private func sectionBanner(label: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(KimaType.meta.monospacedDigit())
                .foregroundStyle(color)
                .tracking(0.1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.sm)
        .background(color.opacity(0.06))
        .overlay(alignment: .bottom) {
            Rectangle().fill(color.opacity(0.18)).frame(height: 1)
        }
    }

    // MARK: - Actions

    private func clearItem(id: String) async {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        let removed = history.remove(at: idx)
        let ok = (try? await env.client.clearDownloadHistoryItem(id: id)) ?? false
        if !ok {
            history.insert(removed, at: min(idx, history.count))
            toast.show("couldn't remove it. try again.", style: .error)
        }
    }

    private func clearAll() async {
        let previous = history
        history = []
        let ok = (try? await env.client.clearAllDownloadHistory()) ?? false
        if !ok {
            history = previous
            toast.show("couldn't clear history. try again.", style: .error)
        }
    }

    private func retry(id: String) async {
        guard !retryingIds.contains(id) else { return }
        retryingIds.insert(id)
        defer { retryingIds.remove(id) }
        do {
            _ = try await env.client.retryDownload(id: id)
            // Job moved to active queue — remove from history view
            history.removeAll { $0.id == id }
            toast.show("download restarted", style: .success)
        } catch {
            toast.show(AcquirePermission.failureMessage(error, fallback: "couldn't retry. try again."), style: .error)
        }
    }
}

// MARK: - History row

private struct HistoryRow: View {
    let item: DownloadHistoryItem
    let isRetrying: Bool
    let onRetry: (() -> Void)?
    let onClear: () -> Void

    private var isCompleted: Bool { item.status == "completed" }
    private var isFailed: Bool    { item.status == "failed" || item.status == "exhausted" }


    private var statusTime: String {
        let src = item.completedAt ?? item.createdAt
        return Formatters.relativeTimeString(fromISO8601: src)
    }

    var body: some View {
        HStack(alignment: .top, spacing: KimaSpacing.md) {
            // Status icon
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(KimaColor.positive)
                    .padding(.top, 2)  // optical: sits the icon on the first text line
            } else {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(KimaColor.danger)
                    .padding(.top, 2)  // optical: sits the icon on the first text line
            }

            // Content
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(item.subject)
                    .font(KimaType.captionStrong)
                    .foregroundStyle(KimaColor.textPrimary)
                    .lineLimit(1)

                HStack(spacing: KimaSpacing.xs) {
                    Label(item.type, systemImage: item.type == "album" ? "opticaldisc" : "music.mic")
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)
                        .labelStyle(.titleAndIcon)
                    Text("•").font(KimaType.meta).foregroundStyle(KimaColor.textMuted)
                    Text(statusTime).font(KimaType.meta.monospacedDigit()).foregroundStyle(KimaColor.textMuted)
                }

                if let err = item.error, !err.isEmpty {
                    Text(err)
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.danger.opacity(0.85))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            // Actions
            HStack(spacing: KimaSpacing.sm) {
                if isFailed, let onRetry {
                    ActivityRowActionButton(
                        systemImage: "arrow.clockwise",
                        accessibilityLabel: "retry download",
                        isLoading: isRetrying,
                        action: onRetry
                    )
                }
                ActivityRowActionButton(
                    systemImage: "xmark",
                    accessibilityLabel: "remove from history",
                    action: onClear
                )
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.md)
        // No coloured side-stripe: the row labels carry the state.
        .overlay(alignment: .bottom) {
            KimaHairline()
        }
    }
}
