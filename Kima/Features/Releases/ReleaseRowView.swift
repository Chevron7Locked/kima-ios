import SwiftUI

// MARK: - ReleaseRowView
//
// One Release Radar row: cover | artist, title, date | status badge | download button.
// `coverUrl` is an absolute Lidarr URL, so it uses RemoteArtworkImage, not CoverArtImage.

struct ReleaseRowView: View {
    let release: ReleaseItem
    let isDownloading: Bool
    /// Nil when this listener may not start downloads: the button is hidden.
    let onDownload: (() -> Void)?

    // MARK: - Date formatting

    /// Human-readable release date. Attempts ISO full-date parse on the first 10
    /// characters (YYYY-MM-DD prefix); falls back to full ISO parse; last resort is the
    /// raw string, never crashing.
    private var dateLabel: String {
        let raw = String(release.releaseDate.prefix(10))
        if let date = Formatters.iso8601FullDate.date(from: raw) {
            return Formatters.displayDate(date)
        }
        if let date = Formatters.parseISO8601(release.releaseDate) {
            return Formatters.displayDate(date)
        }
        return raw
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: KimaSpacing.md) {
            artworkView

            infoStack

            Spacer(minLength: 0)

            HStack(spacing: KimaSpacing.sm) {
                statusBadge
                if release.canDownload, let onDownload {
                    downloadButton(onDownload)
                }
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.md)
    }

    // MARK: - Artwork

    private var artworkView: some View {
        RemoteArtworkImage(
            urlString: release.coverUrl,
            accessibilityLabel: "\(release.title) cover",
            maxPixel: 168
        )
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(KimaColor.hairline, lineWidth: 1)
        )
    }

    // MARK: - Info stack

    private var infoStack: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            Text(release.title.lowercased())
                .font(KimaType.headline)
                .foregroundStyle(KimaColor.textPrimary)
                .lineLimit(1)
            Text(release.artistName.lowercased())
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
                .lineLimit(1)
            Text(dateLabel)
                .font(KimaType.meta)
                .foregroundStyle(KimaColor.textMuted)
        }
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        switch release.status {
        case .upcoming:
            KimaTag(text: "soon", tone: .strong)
        case .available:
            KimaTag(text: "in library")
        case .released:
            EmptyView()
        }
    }

    // MARK: - Download button

    private func downloadButton(_ onDownload: @escaping () -> Void) -> some View {
        Button(action: onDownload) {
            Group {
                if isDownloading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(KimaColor.brand)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(KimaColor.textSecondary)
                }
            }
            .frame(width: 32, height: 32)
            .kimaHitTarget(growsLayout: false)
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
        .accessibilityLabel(isDownloading ? "downloading" : "download")
    }
}
