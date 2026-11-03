import SwiftUI

// Extracted from AlbumHeroView.swift — playback controls are a separate concern from the
// hero's cover/title/metadata.

// MARK: - Action bar

struct AlbumActionBarView: View {
    let album: Album
    let isOwned: Bool
    let isThisAlbumPlaying: Bool
    let vm: AlbumDetailViewModel
    /// Opens the metadata editor; nil hides "edit details" (albums not in the library).
    var onEdit: (() -> Void)? = nil

    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    /// True when the album detail response includes at least one missing-track slot.
    private var hasMissingTracks: Bool {
        !(album.missingTracks ?? []).isEmpty
    }

    var body: some View {
        content
            .task { await env.acquire.refresh(client: env.client) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            HStack(spacing: KimaSpacing.md) {
                if isOwned {
                    playPauseButton
                    shuffleButton
                } else if album.mbid != nil || album.rgMbid != nil {
                    if env.acquire.canAcquire {
                        downloadButton
                    } else if env.acquire.isLocked {
                        Text(AcquirePermission.lockedLabel)
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textMuted)
                    }
                }
                Spacer(minLength: 0)
                if isOwned { moreMenu }
            }
            // Partially-owned: the gap-filler control does NOT share the play row. It gets a quiet annotation
            // line under the controls, count included,
            // so it reads as a fact about the library, not a second call-to-action.
            if isOwned && hasMissingTracks && env.acquire.canAcquire && (album.mbid != nil || album.rgMbid != nil) {
                downloadMissingButton
            }
        }
    }

    // Play shows Pause when THIS album is the one playing. The view's one amber control: a flat disc.
    private var playPauseButton: some View {
        KimaHeroPlayButton(isPlaying: isThisAlbumPlaying) {
            if isThisAlbumPlaying {
                player.togglePlayPause()
            } else {
                let tracks = album.tracksInOrder
                if !tracks.isEmpty { player.play(tracks: tracks, startAt: 0, shuffle: false) }
            }
        }
    }

    private var shuffleButton: some View {
        KimaActionPill(title: "shuffle", systemImage: "shuffle") {
            let tracks = album.tracksInOrder
            if !tracks.isEmpty { player.play(tracks: tracks, startAt: 0, shuffle: true) }
        }
    }

    /// Queue, playlist and edit: used less than play/shuffle, so they wait one tap away.
    private var moreMenu: some View {
        KimaMoreMenu(label: "album actions") {
            Button("add to queue", systemImage: "text.badge.plus") {
                let tracks = album.tracksInOrder
                guard !tracks.isEmpty else { return }
                announceEnqueue(player.enqueue(tracks: tracks), name: album.effectiveTitle, in: toast)
            }
            Button("add to playlist", systemImage: "music.note.list") {
                vm.addToPlaylist(album, using: env.playlistPicker)
            }
            if let onEdit {
                Button("edit details", systemImage: "pencil", action: onEdit)
            }
        }
    }

    private var downloadButton: some View {
        Button {
            Task { await vm.downloadAlbum(album, client: env.client, toast: toast) }
        } label: {
            Label("download", systemImage: "arrow.down.circle.fill")
                .font(KimaType.headline)
                .foregroundStyle(KimaColor.textPrimary)
                .padding(.horizontal, KimaSpacing.xl)
                .padding(.vertical, KimaSpacing.md)
                .background(KimaColor.fillQuiet, in: Capsule())
                .overlay(Capsule().strokeBorder(KimaColor.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("download album")
    }

    /// Quiet annotation line for a partially-owned album (count states intent unambiguously:
    /// only the named gap is fetched). Same endpoint as downloadButton; Lidarr fills only gaps.
    /// Deliberately text-only — no capsule, no glow; the play row keeps sole prominence.
    private var downloadMissingButton: some View {
        let n = (album.missingTracks ?? []).count
        return Button {
            Task { await vm.downloadAlbum(album, client: env.client, toast: toast) }
        } label: {
            HStack(spacing: KimaSpacing.xs) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11))
                Text(n == 1 ? "download 1 missing track" : "download \(n) missing tracks")
            }
            .font(KimaType.caption)
            .foregroundStyle(KimaColor.textSecondary)
            .padding(.vertical, KimaSpacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(n == 1 ? "download 1 missing track" : "download \(n) missing tracks")
    }
}
