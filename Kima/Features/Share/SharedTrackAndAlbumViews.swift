import SwiftUI

// MARK: - SharedTrackBody

/// Centered body for an entityType == "track" share link.
/// Large artwork, title + artist + album metadata, and a play/pause button.
struct SharedTrackBody: View {
    let track: SharedTrack
    let vm: SharedContentViewModel
    let dismiss: DismissAction

    private var coverId: String? { track.album?.effectiveCoverId }
    private var isPlaying: Bool { vm.currentTrackId == track.id && vm.isPlaying }

    var body: some View {
        VStack(spacing: 0) {
            // Close button — top right
            HStack {
                Spacer()
                KimaCloseButton(label: "close", id: "share-close", kind: .screen) { dismiss() }
            }
            .padding([.top, .trailing], KimaSpacing.lg)

            Spacer()

            // Artwork
            SharedCoverImage(coverId: coverId, vm: vm, size: 512)
                .frame(width: 240, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(KimaColor.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)

            // Metadata
            VStack(spacing: KimaSpacing.xs) {
                KimaKicker(title: "shared track")
                .padding(.top, KimaSpacing.xl)

                Text(track.title.lowercased())
                    .font(KimaType.pageTitle)
                    .foregroundStyle(KimaColor.textPrimary)
                    .tracking(0.5)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let artist = track.album?.artist?.name {
                    Text(artist)
                        .font(KimaType.body)
                        .foregroundStyle(KimaColor.textSecondary)
                }
                if let album = track.album?.title {
                    Text(album)
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                }
            }
            .padding(.horizontal, KimaSpacing.xxl)

            // Play / pause
            KimaHeroPlayButton(isPlaying: isPlaying) {
                vm.togglePlayPause(trackId: track.id)
            }
            .padding(.top, KimaSpacing.xl)

            Spacer()
        }
    }
}

// MARK: - SharedAlbumBody

/// Scrollable body for an entityType == "album" share link.
/// Header: blurred backdrop + cover art + album title + artist.
/// Below: track list ordered by trackNo with play-on-tap.
struct SharedAlbumBody: View {
    let album: SharedAlbum
    let vm: SharedContentViewModel
    let dismiss: DismissAction

    var body: some View {
        SharedTrackListPage(rows: album.tracks.enumerated().map { .init(id: $1.id, index: $1.trackNo ?? ($0 + 1), track: $1) },
                            vm: vm) { header }
    }

    // MARK: - Hero header

    private var header: some View {
        SharedHeroHeader(coverId: album.effectiveCoverId, kicker: "shared album",
                         title: (album.title ?? "unknown album").lowercased(), vm: vm, dismiss: dismiss) {
            if let artist = album.artist?.name {
                Text(artist)
                    .font(KimaType.captionStrong)
                    .foregroundStyle(KimaColor.textSecondary)
            }
        }
    }
}
