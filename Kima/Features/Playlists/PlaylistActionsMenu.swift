import SwiftUI

// MARK: - PlaylistActionsMenu

/// The playlist page's "•••" menu. Every row says what it does; the page toasts each change. Owners can make
/// the playlist public or private, share or turn off its link, rename and delete it; anyone can hide it.
struct PlaylistActionsMenu: View {
    let playlist: PlaylistDetail
    /// A share link was made on this page, so it can be turned off.
    let hasShareLink: Bool
    /// A share link is being made.
    let isWorking: Bool
    let onTogglePublic: () -> Void
    let onShare: () -> Void
    let onStopSharing: () -> Void
    let onToggleHidden: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    private var isOwner: Bool { playlist.isOwner == true }

    var body: some View {
        KimaMoreMenu(label: "playlist actions", isWorking: isWorking) {
            if isOwner {
                Section {
                    if playlist.isPublic == true {
                        Button("make private", systemImage: "lock", action: onTogglePublic)
                    } else {
                        Button("make public", systemImage: "globe", action: onTogglePublic)
                    }
                    Button("share link", systemImage: "square.and.arrow.up", action: onShare)
                    if hasShareLink {
                        Button("turn off share link", systemImage: "xmark.circle", action: onStopSharing)
                    }
                }
            }
            Section {
                if playlist.isHidden == true {
                    Button("show in playlists", systemImage: "eye", action: onToggleHidden)
                } else {
                    Button("hide from playlists", systemImage: "eye.slash", action: onToggleHidden)
                }
                if isOwner {
                    Button("rename", systemImage: "pencil", action: onRename)
                }
            }
            if isOwner {
                Button("delete playlist", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
        .accessibilityIdentifier("playlist-actions")
    }
}
