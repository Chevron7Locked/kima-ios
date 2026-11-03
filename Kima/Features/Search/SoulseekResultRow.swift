import SwiftUI

// MARK: - SoulseekResultRow
//
// One Soulseek peer-file hit. No cover art exists, so the leading slot is a format badge;
// otherwise it mirrors `ReleaseRowView`.

struct SoulseekResultRow: View {
    let result:        SoulseekResult
    let isDownloading: Bool
    /// Nil when this listener may not start downloads: the button is hidden.
    let onDownload:    (() -> Void)?

    private var isLossless: Bool { result.format.lowercased() == "flac" }

    // MARK: - Body

    var body: some View {
        HStack(spacing: KimaSpacing.md) {
            formatBadge
            infoStack
            Spacer(minLength: 0)
            if let onDownload { downloadButton(onDownload) }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.md)
    }

    // MARK: - Format badge

    private var formatBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                .fill(KimaColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                        .strokeBorder(KimaColor.hairline, lineWidth: 1)
                )
            Text(result.format.uppercased())
                .font(KimaType.meta)
                .foregroundStyle(isLossless ? KimaColor.textPrimary : KimaColor.textMuted)
                .tracking(0.4)
        }
        .frame(width: KimaLayout.minTouchTarget, height: KimaLayout.minTouchTarget)
    }

    // MARK: - Info stack

    private var infoStack: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            Text(result.parsedTitle ?? result.filename)
                .font(KimaType.headline)
                .foregroundStyle(KimaColor.textPrimary)
                .lineLimit(1)

            if let secondary = secondaryLine {
                Text(secondary)
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textSecondary)
                    .lineLimit(1)
            }

            Text(metaLine)
                .font(KimaType.meta.monospacedDigit())
                .foregroundStyle(KimaColor.textMuted)
                .lineLimit(1)
        }
    }

    /// "Artist · Album" from the server's best-effort path-parsed metadata — nil when neither
    /// piece parsed (e.g. a flat, non-nested peer share).
    private var secondaryLine: String? {
        let parts = [result.parsedArtist, result.parsedAlbum].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "FLAC · 320kbps · 8.4 MB · someuser" — format · bitrate (omitted when unknown/0) ·
    /// file size · the peer's username.
    private var metaLine: String {
        var parts = [result.format.uppercased()]
        if result.bitrate > 0 { parts.append("\(result.bitrate)kbps") }
        parts.append(Self.sizeFormatter.string(fromByteCount: Int64(result.size)))
        parts.append(result.username)
        return parts.joined(separator: " · ")
    }

    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    // MARK: - Download button

    private func downloadButton(_ onDownload: @escaping () -> Void) -> some View {
        KimaIconDiscButton(systemName: "arrow.down", glyphSize: 15,
                           label: isDownloading ? "downloading" : "download from Soulseek",
                           isLoading: isDownloading, action: onDownload)
    }
}
