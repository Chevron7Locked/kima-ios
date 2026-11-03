import SwiftUI

// MARK: - Private modifier

private struct LibraryItemMenuModifier: ViewModifier {
    let onPlay: () -> Void
    let onPlayNext: (() -> Void)?
    let onQueue: (() -> Void)?
    let onAddToPlaylist: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                // Play — always present
                Button {
                    onPlay()
                } label: {
                    Label("play", systemImage: "play.fill")
                }

                // Play Next — present only when the caller supplies a handler
                if let onPlayNext {
                    Button {
                        onPlayNext()
                    } label: {
                        Label("play next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                }

                // Add to Queue — present only when caller supplies a handler
                if let onQueue {
                    Button {
                        onQueue()
                    } label: {
                        Label("add to queue", systemImage: "text.badge.plus")
                    }
                }

                // Add to Playlist — shown when the caller supplies a handler (presents the picker)
                if let onAddToPlaylist {
                    Button {
                        onAddToPlaylist()
                    } label: {
                        Label("add to playlist", systemImage: "music.note.list")
                    }
                }
            }
    }
}

// MARK: - Public View extension (exact contract)

extension View {
    /// Attaches a long-press context menu to any library row: Play (always), Play Next / Add to
    /// Queue / Add to Playlist (each only when its callback is non-nil).
    func libraryItemMenu(
        onPlay: @escaping () -> Void,
        onPlayNext: (() -> Void)? = nil,
        onQueue: (() -> Void)? = nil,
        onAddToPlaylist: (() -> Void)? = nil
    ) -> some View {
        modifier(LibraryItemMenuModifier(
            onPlay: onPlay,
            onPlayNext: onPlayNext,
            onQueue: onQueue,
            onAddToPlaylist: onAddToPlaylist
        ))
    }
}
