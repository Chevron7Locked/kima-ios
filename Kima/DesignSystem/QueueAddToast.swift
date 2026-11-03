import SwiftUI

// MARK: - Queue toasts
// One wording for what "play next" and "add to queue" did, shared by every surface; views must not write their own.
// @MainActor: ToastCenter.show is main-actor-isolated.

/// Toast for a `playNext` outcome. `failedAlbums` > 0 adds "couldn't load n albums".
@MainActor
func announcePlayNext(_ outcome: QueueAddOutcome, failedAlbums: Int = 0, in toast: ToastCenter) {
    if outcome == .added {
        show("playing next", failedAlbums: failedAlbums, in: toast)
    } else {
        announceStarted(outcome, failedAlbums: failedAlbums, in: toast)
    }
}

/// Toast for an `enqueue` outcome. `name` is what was added ("added <name> to queue"); nil for a
/// single track.
@MainActor
func announceEnqueue(_ outcome: QueueAddOutcome, name: String? = nil, failedAlbums: Int = 0, in toast: ToastCenter) {
    if outcome == .added {
        show(name.map { "added \($0) to queue" } ?? "added to queue", failedAlbums: failedAlbums, in: toast)
    } else {
        announceStarted(outcome, failedAlbums: failedAlbums, in: toast)
    }
}

/// "couldn't load 1 album" / "couldn't load 3 albums".
func couldntLoadAlbumsText(_ n: Int) -> String {
    "couldn't load \(n) album\(n == 1 ? "" : "s")"
}

/// The success text, or — when some albums failed — the same text plus the failure, as an error.
@MainActor
private func show(_ message: String, failedAlbums: Int, in toast: ToastCenter, style: ToastStyle = .success) {
    if failedAlbums > 0 {
        toast.show("\(message). \(couldntLoadAlbumsText(failedAlbums))", style: .error)
    } else {
        toast.show(message, style: style)
    }
}

/// The outcomes where nothing was added because playback started instead.
@MainActor
private func announceStarted(_ outcome: QueueAddOutcome, failedAlbums: Int, in toast: ToastCenter) {
    switch outcome {
    case .added, .startedIdle:
        show("started playback", failedAlbums: failedAlbums, in: toast)
    case .stoppedAudiobook:
        show("stopped the audiobook and started playback", failedAlbums: failedAlbums, in: toast, style: .info)
    case .stoppedPodcast:
        show("stopped the podcast and started playback", failedAlbums: failedAlbums, in: toast, style: .info)
    }
}

/// The long-press items for a library track: play next, add to queue, add to playlist.
struct TrackQueueMenuItems: View {
    let track: Track
    let player: PlaybackController
    let playlistPicker: PlaylistPickerModel
    let toast: ToastCenter

    var body: some View {
        Button {
            announcePlayNext(player.playNext(track), in: toast)
        } label: {
            Label("play next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button {
            announceEnqueue(player.enqueue(track: track), in: toast)
        } label: {
            Label("add to queue", systemImage: "text.badge.plus")
        }
        Button {
            playlistPicker.present(.tracks([track]))
        } label: {
            Label("add to playlist", systemImage: "music.note.list")
        }
    }
}
