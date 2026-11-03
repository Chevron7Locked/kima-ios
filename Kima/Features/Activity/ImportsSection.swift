import SwiftUI

// GET /api/spotify/imports — all import jobs (active + past).
// Polled on appear + driven by env.events.importTick (SSE import:progress events).

private let activeStatuses: Set<String> = [
    "pending", "fetching", "downloading", "scanning", "creating_playlist", "matching_tracks"
]

/// Imports tab body. Lightweight: active imports with cancel, past imports (read-only rows).
struct ImportsSection: View {
    @Environment(AppEnvironment.self) private var env

    @State private var isLoading = false
    @State private var cancellingIds: Set<String> = []

    var body: some View {
        ZStack {
            if isLoading && imports.isEmpty {
                loadingState
            } else if env.activity.importsFailed && imports.isEmpty {
                KimaErrorState(message: "couldn't load imports") { Task { await fetchImports() } }
            } else if imports.isEmpty {
                emptyState
            } else {
                importList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Runs on appear and on every import SSE tick; a newer tick cancels the older fetch.
        .task(id: env.events.importTick) { await fetchImports() }
    }

    // MARK: - Fetch

    /// Kept on `env.activity` so the list survives the sheet closing.
    private var imports: [ImportJob] {
        get { env.activity.imports }
        nonmutating set { env.activity.imports = newValue }
    }

    private func fetchImports() async {
        if imports.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            imports = try await env.client.getUserImports()
            env.activity.importsFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            env.activity.importsFailed = true
        }
    }

    // MARK: - States

    private var loadingState: some View {
        KimaLoadingState(text: "loading imports…") { Task { await fetchImports() } }
    }

    private var emptyState: some View {
        KimaEmptyState(icon: "list.bullet", title: "no imports yet", message: "imported playlists show up here")
    }

    // MARK: - List

    private var importList: some View {
        let active = imports.filter { activeStatuses.contains($0.status) }
        let past   = imports.filter { !activeStatuses.contains($0.status) }
        return ScrollView {
            LazyVStack(spacing: 0) {
                if !active.isEmpty {
                    activeHeader(count: active.count)
                    ForEach(active) { job in
                        ImportJobRow(job: job,
                                     isCancelling: cancellingIds.contains(job.id),
                                     onCancel: { Task { await cancel(id: job.id) } })
                    }
                }
                if !past.isEmpty {
                    if !active.isEmpty { divider }
                    ForEach(past) { job in
                        ImportJobRow(job: job,
                                     isCancelling: false, onCancel: nil)
                    }
                }
                Spacer(minLength: KimaSpacing.huge)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func activeHeader(count: Int) -> some View {
        HStack(spacing: KimaSpacing.sm) {
            KimaKicker(title: String(format: "%d active", count), dotColor: KimaColor.textSecondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.md)
        .overlay(alignment: .bottom) {
            KimaHairline()
        }
    }

    private var divider: some View {
        HStack(spacing: KimaSpacing.sm) {
            Text("previous")
                .font(KimaType.meta)
                .foregroundStyle(KimaColor.textMuted)
                .tracking(0.1)
            KimaHairline()
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.sm)
    }

    // MARK: - Cancel

    private func cancel(id: String) async {
        guard !cancellingIds.contains(id) else { return }
        cancellingIds.insert(id)
        defer { cancellingIds.remove(id) }
        _ = try? await env.client.cancelImport(id: id)
        await fetchImports()
    }
}

// MARK: - Import job row

private struct ImportJobRow: View {
    let job: ImportJob
    let isCancelling: Bool
    let onCancel: (() -> Void)?

    private var isActive: Bool { activeStatuses.contains(job.status) }

    private var statusLabel: String {
        switch job.status {
        case "pending":           return "pending"
        case "fetching":          return "fetching"
        case "downloading":       return "downloading"
        case "scanning":          return "scanning"
        case "creating_playlist": return "creating"
        case "matching_tracks":   return "matching"
        case "completed":         return "done"
        case "failed":            return "failed"
        case "cancelled":         return "cancelled"
        default:                  return job.status.lowercased()
        }
    }

    private var statusColor: Color {
        if isActive || job.status == "completed" { return KimaColor.textSecondary }
        if job.status == "failed"    { return KimaColor.danger }
        return KimaColor.textMuted
    }


    private var age: String {
        Formatters.relativeTimeString(fromISO8601: job.createdAt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: KimaSpacing.md) {
            // Status icon
            Group {
                if isActive {
                    if isCancelling {
                        ProgressView().controlSize(.small).tint(KimaColor.textMuted)
                    } else {
                        ProgressView().controlSize(.small).tint(KimaColor.textSecondary)
                    }
                } else if job.status == "completed" {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(KimaColor.positive)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(KimaColor.danger)
                }
            }
            .frame(width: 16, height: 16)
            .padding(.top, 2)  // optical: sits the icon on the first text line

            // Content
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(job.playlistName)
                    .font(KimaType.captionStrong)
                    .foregroundStyle(KimaColor.textPrimary)
                    .lineLimit(1)

                HStack(spacing: KimaSpacing.xs) {
                    Text(statusLabel)
                        .font(KimaType.meta)
                        .foregroundStyle(statusColor)
                    if isActive && job.albumsTotal > 0 {
                        Text("--").font(KimaType.meta).foregroundStyle(KimaColor.textMuted)
                        Text("\(job.albumsCompleted)/\(job.albumsTotal) \(job.albumsTotal == 1 ? "album" : "albums")")
                            .font(KimaType.meta.monospacedDigit()).foregroundStyle(KimaColor.textMuted)
                    }
                    Text("--").font(KimaType.meta).foregroundStyle(KimaColor.textMuted)
                    Text(age).font(KimaType.meta.monospacedDigit()).foregroundStyle(KimaColor.textMuted)
                }

                // Progress bar for active imports with album counts
                if isActive && job.albumsTotal > 0 {
                    KimaProgressBar(
                        fraction: Double(job.albumsCompleted) / Double(job.albumsTotal),
                        track: KimaColor.hairline
                    )

                }

                if job.status == "failed", let err = job.error {
                    Text(err)
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.danger.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Cancel button — shown only while the job is active; isCancelling disables it
            // (no spinner: the status icon area already shows the cancelling state).
            if isActive, let onCancel {
                ActivityRowActionButton(
                    systemImage: "xmark",
                    accessibilityLabel: "cancel import",
                    action: onCancel
                )
                .disabled(isCancelling)
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.md)
        // No coloured side-stripe: statusLabel carries the state.
        .overlay(alignment: .bottom) {
            KimaHairline()
        }
    }
}
