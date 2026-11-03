import SwiftUI

// Shared sub-components used across the three entity body views (playlist, track, album).
// Internal access: module-only, not exported outside the app target.

// MARK: - SharedCoverImage

/// Displays a cover art image via the public share cover-art proxy (no auth headers needed).
/// Delegates to RemoteArtworkImage so caching and fallback placeholder behaviour are identical.
struct SharedCoverImage: View {
    let coverId: String?
    let vm: SharedContentViewModel
    let size: Int
    var accessibilityLabel: String = "album artwork"

    var body: some View {
        RemoteArtworkImage(
            urlString: coverId.flatMap { vm.coverURL(for: $0, size: size) }?.absoluteString,
            accessibilityLabel: accessibilityLabel
        )
    }
}

// MARK: - SharedHeroHeader

/// The hero header of the playlist and album share pages: blurred artwork backdrop, close
/// button top-right, cover thumbnail, kicker, title, and a caller-supplied meta line.
struct SharedHeroHeader<Meta: View>: View {
    let coverId: String?
    let kicker: String
    let title: String
    let vm: SharedContentViewModel
    let dismiss: DismissAction
    @ViewBuilder var meta: () -> Meta

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Blurred artwork backdrop
            if let coverId {
                SharedCoverImage(coverId: coverId, vm: vm, size: 512, accessibilityLabel: "")
                    .frame(height: 220)
                    .blur(radius: 40)
                    .opacity(0.2)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [.clear, KimaColor.base],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            } else {
                KimaColor.base.frame(height: 220)
            }

            VStack(alignment: .leading, spacing: 0) {
                // Close button — top right
                HStack {
                    Spacer()
                    KimaCloseButton(label: "close", id: "share-close", kind: .screen) { dismiss() }
                }
                .padding(.top, KimaSpacing.lg)

                Spacer(minLength: KimaSpacing.xl)

                HStack(alignment: .bottom, spacing: KimaSpacing.lg) {
                    // Cover art thumbnail
                    SharedCoverImage(coverId: coverId, vm: vm, size: 256)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(KimaColor.hairline, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)

                    VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                        KimaKicker(title: kicker)
                        Text(title)
                            .font(KimaType.pageTitle)
                            .foregroundStyle(KimaColor.textPrimary)
                            .tracking(0.5)
                            .lineLimit(2)
                        meta()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, KimaSpacing.md)
            }
            .padding(.horizontal, KimaSpacing.lg)
        }
    }
}

// MARK: - SharedTrackListPage

/// A shared playlist or album page: its hero header, then its numbered tracks between hairlines.
struct SharedTrackListPage<Header: View>: View {
    struct Row { let id: String; let index: Int; let track: SharedTrack }

    let rows: [Row]
    let vm: SharedContentViewModel
    @ViewBuilder let header: () -> Header

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header()
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        SharedTrackRowButton(track: row.track, vm: vm, index: row.index)
                        if i < rows.count - 1 {
                            KimaHairline()
                                .padding(.horizontal, KimaSpacing.lg)
                        }
                    }
                }
                .padding(.top, KimaSpacing.sm)
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - SharedTrackRowButton

/// Tappable track row: index number (or play icon), title + artist, duration. Highlights in
/// amber and toggles a play/pause icon while this track is the active preview.
struct SharedTrackRowButton: View {
    let track: SharedTrack
    let vm: SharedContentViewModel
    var index: Int? = nil      // optional 1-based number prefix

    private var isThisTrack: Bool { vm.currentTrackId == track.id }

    var body: some View {
        Button {
            vm.togglePlayPause(trackId: track.id)
        } label: {
            HStack(spacing: KimaSpacing.md) {
                // Index / playback indicator
                ZStack {
                    if isThisTrack {
                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(KimaColor.brand)
                    } else if let n = index {
                        Text("\(n)")
                            .font(KimaType.meta.monospacedDigit())
                            .foregroundStyle(KimaColor.textMuted)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(KimaColor.textMuted)
                    }
                }
                .frame(width: 20)

                VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                    Text(track.title.lowercased())
                        .font(KimaType.body)
                        .foregroundStyle(isThisTrack ? KimaColor.brand : KimaColor.textPrimary)
                        .lineLimit(1)
                    if let artist = track.album?.artist?.name {
                        Text(artist)
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Text(track.duration.durationFormatted)
                    .font(KimaType.meta.monospacedDigit())
                    .foregroundStyle(KimaColor.textMuted)
            }
            .padding(.vertical, KimaSpacing.sm)
            .padding(.horizontal, KimaSpacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

