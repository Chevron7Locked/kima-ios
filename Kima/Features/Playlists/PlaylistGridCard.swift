import SwiftUI

// MARK: - PlaylistGridCard

/// Individual card in the Playlists grid. Faithfully ports the web PlaylistCard component:
/// cover mosaic, name, track count, shared-by user, hidden-view dimming, play button.
struct PlaylistGridCard: View {
    let playlist: PlaylistSummary
    let isHiddenView: Bool
    let onTap: () -> Void
    let onPlay: () -> Void
    let onToggleHide: () -> Void
    /// The play request for this playlist is in flight: the badge spins and taps are ignored.
    var isBusy: Bool = false

    var body: some View {
        KimaCoverCard(title: playlist.name, subtitle: subtitle, isBusy: isBusy, onPlay: onPlay, onTap: onTap) {
            mosaicTile
        } accessory: {
            if playlist.isOwner != true { hideOverlay }
        }
        .opacity(isHiddenView ? 0.6 : 1)
    }

    /// "owner · N songs" for someone else's playlist, else the count alone.
    private var subtitle: String {
        let count = playlist.trackCount ?? 0
        let songs = "\(count) \(count == 1 ? "song" : "songs")"
        guard playlist.isOwner != true, let user = playlist.user else { return songs }
        return "\(user.username) · \(songs)"
    }

    // MARK: - Sub-views

    private var mosaicTile: some View {
        PlaylistMosaicView(
            coverIds: playlistMosaicCoverIds(from: playlist.items),
            cellSize: 120
        )
    }

    private var hideOverlay: some View {
        Button(action: onToggleHide) {
            Image(systemName: playlist.isHidden == true ? "eye" : "eye.slash")
                .font(.system(size: 12))
                .foregroundStyle(playlist.isHidden == true ? KimaColor.textPrimary : KimaColor.textMuted)
                .frame(width: 28, height: 28)
                .background(KimaColor.discGlass, in: Circle())
                .overlay(Circle().strokeBorder(KimaColor.hairline, lineWidth: 1))
                .kimaHitTarget(growsLayout: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playlist.isHidden == true ? "show playlist" : "hide playlist")
        .padding(KimaSpacing.sm)
    }
}

// MARK: - PlaylistGridCardSkeleton

/// Animated loading placeholder matching the grid card dimensions.
struct PlaylistGridCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                .fill(KimaColor.surface)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Capsule()
                    .fill(KimaColor.surface)
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
                Capsule()
                    .fill(KimaColor.surface)
                    .frame(width: 60, height: 10)
            }
            .padding(.horizontal, KimaSpacing.xs)
        }
        .kimaSkeletonPulse()
    }
}
