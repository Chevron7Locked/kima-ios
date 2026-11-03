import SwiftUI

// MARK: - PlaylistPickerRow

/// A single tappable playlist row in `PlaylistPickerSheet`: 2×2 cover mosaic + name + track
/// count + add affordance. Reuses `PlaylistMosaicView` so the artwork matches the Playlists
/// library grid exactly.
struct PlaylistPickerRow: View {
    let playlist: PlaylistSummary
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: KimaSpacing.md) {
                PlaylistMosaicView(coverIds: playlistMosaicCoverIds(from: playlist.items), cellSize: 60)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                            .strokeBorder(KimaColor.hairline, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                    Text(playlist.name.lowercased())
                        .font(KimaType.captionStrong)
                        .foregroundStyle(KimaColor.textPrimary)
                        .lineLimit(1)
                    Text(trackCountLabel)
                        .font(KimaType.meta)
                        .monospacedDigit()
                        .foregroundStyle(KimaColor.textMuted)
                }

                Spacer(minLength: 0)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(KimaColor.textSecondary)
            }
            .padding(.horizontal, KimaSpacing.md)
            .padding(.vertical, KimaSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var trackCountLabel: String {
        let n = playlist.trackCount ?? 0
        return "\(n) \(n == 1 ? "track" : "tracks")"
    }
}
