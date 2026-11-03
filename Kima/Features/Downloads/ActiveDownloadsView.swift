import SwiftUI

// Shows active (pending/processing) Lidarr acquisition jobs + failed album notifications.
// Refresh: SSE downloadTick + a 30-second safety poll started on appear, stopped on disappear.
// Cancel: DELETE /api/downloads/:id. Dismiss failed: DELETE /api/downloads/failed/:id.

struct ActiveDownloadsView: View {
    @State private var vm = ActiveDownloadsViewModel()
    // Debounces the SSE-tick-driven refresh below — a burst of ticks would otherwise fire
    // a concurrent initialLoad (getActiveDownloads + getFailedDownloads) per tick.
    @State private var downloadTickTask: Task<Void, Never>?

    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    /// True inside the activity sheet: no backdrop of its own, so the sheet's surface shows through.
    var embedded = false

    var body: some View {
        screen
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Initial load, then the 30-second safety poll.
        .task {
            await vm.initialLoad(client: env.client)
            vm.startPolling(client: env.client)
        }
        .onDisappear {
            vm.stopPolling()
            downloadTickTask?.cancel()
        }
        .refreshable { await vm.initialLoad(client: env.client) }
        // Debounced: cancels the prior pending refresh and waits 400ms, so a burst of ticks
        // collapses into a single refresh instead of one per tick.
        .onChange(of: env.events.downloadTick) { _, _ in
            downloadTickTask?.cancel()
            downloadTickTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await vm.initialLoad(client: env.client)
            }
        }
    }

    // MARK: - Backdrop

    /// Pushed from More it sits on the screen canvas like every other pushed screen; embedded in
    /// the activity sheet it stays transparent (an opaque base here painted the sheet's downloads
    /// tab black while its other tabs showed the sheet colour).
    @ViewBuilder
    private var screen: some View {
        if embedded {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                KimaScreenHeader(title: "downloads")
                content.frame(maxHeight: .infinity)
            }
            .kimaScreenCanvas()
        }
    }

    // MARK: - Content routing

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.downloads.isEmpty && vm.failedAlbums.isEmpty {
            loadingState
        } else if let err = vm.error, vm.downloads.isEmpty && vm.failedAlbums.isEmpty {
            errorState(err)
        } else if vm.downloads.isEmpty && vm.failedAlbums.isEmpty {
            emptyState
        } else {
            downloadList
        }
    }

    // MARK: - States

    private var loadingState: some View {
        KimaLoadingState { Task { await vm.initialLoad(client: env.client) } }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        KimaErrorState(message: message) { Task { await vm.initialLoad(client: env.client) } }
    }

    private var emptyState: some View {
        KimaEmptyState(
            icon: "arrow.down.circle",
            title: "no active downloads",
            message: "albums you download show up here."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Download list

    private var downloadList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !vm.downloads.isEmpty {
                    activeSection
                }
                if !vm.failedAlbums.isEmpty {
                    failedSection
                }
                if vm.downloads.count > 1 {
                    cancelAllRow
                }
                Spacer(minLength: KimaSpacing.lg)
            }
        }
        .scrollContentBackground(.hidden)
        .kimaScrollTopGround()
        .kimaMiniPlayerClearance()
    }

    // MARK: - Cancel all (destructive — its own group at the foot, always confirmed)

    private var cancelAllRow: some View {
        KimaDestructiveRow(
            label: "cancel all",
            confirmTitle: "cancel all downloads?",
            confirmButton: "cancel all",
            cancelButton: "keep downloading"
        ) {
            Task { await vm.cancelAll(client: env.client, toast: toast) }
        }
    }

    // MARK: - Active section

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: String(format: "%d active", vm.downloads.count))

            ForEach(vm.downloads) { job in
                ActiveDownloadRow(
                    job: job,
                    isCancelling: vm.cancellingIds.contains(job.id),
                    onCancel: {
                        Task { await vm.cancelDownload(id: job.id, client: env.client, toast: toast) }
                    }
                )
            }
        }
    }

    // MARK: - Failed section

    private var failedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: "unavailable")

            ForEach(vm.failedAlbums) { album in
                FailedAlbumRow(
                    album: album,
                    isDismissing: vm.dismissingIds.contains(album.id),
                    onDismiss: {
                        Task { await vm.dismissFailed(id: album.id, client: env.client, toast: toast) }
                    }
                )
            }
        }
    }
}
