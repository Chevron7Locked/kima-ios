import SwiftUI

// Row views for ActiveDownloadsView's two list sections. Both are fully self-contained
// (no dependency on ActiveDownloadsView's state beyond the params passed in), split out of
// that file for size.

// MARK: - Active download row

struct ActiveDownloadRow: View {
    let job: DownloadJob
    let isCancelling: Bool
    let onCancel: () -> Void

    private var isProcessing: Bool { job.status == "processing" }
    private var statusColor: Color { isProcessing ? KimaColor.textPrimary : KimaColor.textSecondary }
    /// When it started, in the app's shared wording ("just now", "5m ago").
    private var elapsed: String { Formatters.relativeTimeString(fromISO8601: job.createdAt) }

    var body: some View {
        HStack(alignment: .top, spacing: KimaSpacing.md) {
            // Spinner
            Group {
                if isCancelling {
                    ProgressView()
                        .controlSize(.small)
                        .tint(KimaColor.textMuted)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(KimaColor.brand)
                }
            }
            .frame(width: 16, height: 16)
            .padding(.top, 2)  // optical: sits the icon on the first text line

            // Content
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(job.subject.lowercased())
                    .font(KimaType.captionStrong)
                    .foregroundStyle(KimaColor.textPrimary)
                    .lineLimit(2)

                HStack(spacing: KimaSpacing.sm) {
                    // Status badge
                    Text(job.status.lowercased())
                        .font(KimaType.meta)
                        .foregroundStyle(statusColor)

                    if let statusText = job.metadata?.statusText, !statusText.isEmpty {
                        Text("•")
                            .font(KimaType.meta)
                            .foregroundStyle(KimaColor.textMuted)
                        Text(statusText)
                            .font(KimaType.meta)
                            .foregroundStyle(KimaColor.textMuted)
                    }

                    Text("•")
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)

                    // Type icon
                    Label(job.type, systemImage: job.type == "album" ? "opticaldisc" : "music.mic")
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)
                        .labelStyle(.titleAndIcon)

                    Text("•")
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)

                    Text(elapsed)
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)
                }
            }

            Spacer(minLength: 0)

            // Cancel button
            KimaCloseButton(label: "cancel download", id: "download-cancel", action: onCancel)
                .disabled(isCancelling)
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.md)
        .overlay(alignment: .bottom) {
            KimaHairline()
        }
        // No leading accent bar: the status text and its colour carry the state.
    }
}

// MARK: - Failed album row

struct FailedAlbumRow: View {
    let album: FailedAlbum
    let isDismissing: Bool
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: KimaSpacing.md) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(KimaColor.danger)

            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(album.albumTitle.lowercased())
                    .font(KimaType.captionStrong)
                    .foregroundStyle(KimaColor.textPrimary)
                    .lineLimit(1)
                Text(album.artistName.lowercased())
                    .font(KimaType.meta)
                    .foregroundStyle(KimaColor.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isDismissing {
                ProgressView()
                    .controlSize(.small)
                    .tint(KimaColor.textMuted)
                    .frame(width: KimaLayout.minTouchTarget, height: KimaLayout.minTouchTarget)
            } else {
                KimaCloseButton(label: "dismiss", id: "download-dismiss", action: onDismiss)
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.md)
        .overlay(alignment: .bottom) {
            KimaHairline()
        }
    }
}
