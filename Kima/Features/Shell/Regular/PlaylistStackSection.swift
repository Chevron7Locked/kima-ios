import SwiftUI

// MARK: - PlaylistStackSection

/// `KimaSidebar`'s "Playlist Stack" region — kicker header + loading / empty / list states.
/// Expanded-sidebar only; `KimaSidebar` guards the call site with `!isCollapsed`.
struct PlaylistStackSection: View {
    let playlists: [PlaylistSummary]
    let isLoadingPlaylists: Bool
    /// The playlist open in the content column; its row shows as selected.
    let openPlaylistId: String?
    let onSelectPlaylist: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            KimaKicker(title: "playlists")
                .padding(.horizontal, KimaSpacing.lg)

            if isLoadingPlaylists {
                ProgressView()
                    .tint(KimaColor.textMuted)
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.vertical, KimaSpacing.md)
            } else if playlists.isEmpty {
                Text("no playlists yet")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.vertical, KimaSpacing.sm)
            } else {
                VStack(spacing: KimaSpacing.xs) {
                    ForEach(playlists) { playlist in
                        playlistRow(playlist)
                    }
                }
            }
        }
    }

    private func playlistRow(_ playlist: PlaylistSummary) -> some View {
        let isOpen = playlist.id == openPlaylistId
        return Button {
            onSelectPlaylist(playlist.id)
        } label: {
            HStack(spacing: KimaSpacing.md) {
                Text(playlist.name.lowercased())
                    .font(KimaType.captionStrong)
                    .foregroundStyle(isOpen ? KimaColor.textPrimary : KimaColor.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: KimaSpacing.sm)

                Text("\(playlist.trackCount ?? 0) \((playlist.trackCount ?? 0) == 1 ? "track" : "tracks")")
                    .font(KimaType.meta.monospacedDigit())
                    .foregroundStyle(KimaColor.textMuted)
                    .tracking(0.4)
            }
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.vertical, KimaSpacing.xs + 2)
            // Same accent-tint selected background as the navigation rows above.
            .background(
                isOpen ? KimaColor.brand.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
            )
            .padding(.horizontal, KimaSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOpen ? [.isSelected, .isButton] : .isButton)
    }
}
