import SwiftUI

// MARK: - SharedPlaylistBody

/// Scrollable body for an entityType == "playlist" share link.
/// Header: blurred backdrop + cover art + name + creator + track count.
/// Below: track list with 1-based index numbers and play-on-tap via SharedTrackRowButton.
struct SharedPlaylistBody: View {
    let playlist: SharedPlaylist
    let vm: SharedContentViewModel
    let dismiss: DismissAction

    private var items: [SharedPlaylistItem] { playlist.items ?? [] }
    private var firstCoverId: String? {
        items.first?.track.album?.effectiveCoverId
    }

    var body: some View {
        SharedTrackListPage(rows: items.enumerated().map { .init(id: $1.id, index: $0 + 1, track: $1.track) },
                            vm: vm) { header }
    }

    // MARK: - Hero header

    private var header: some View {
        SharedHeroHeader(coverId: firstCoverId, kicker: "shared playlist",
                         title: playlist.name.lowercased(), vm: vm, dismiss: dismiss) {
            HStack(spacing: KimaSpacing.sm) {
                if let username = playlist.user?.username {
                    Text(username)
                        .font(KimaType.captionStrong)
                        .foregroundStyle(KimaColor.textSecondary)
                    Text("·").foregroundStyle(KimaColor.textMuted)
                }
                Text("\(items.count) \(items.count == 1 ? "song" : "songs")")
                    .font(KimaType.meta)
                    .foregroundStyle(KimaColor.textMuted)
                    .tracking(0.1)
            }
        }
    }
}
