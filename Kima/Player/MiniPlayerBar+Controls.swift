import SwiftUI
import UIKit

extension MiniPlayerBar {
    // MARK: - Drag gesture

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let h = abs(value.translation.width)
                let v = abs(value.translation.height)
                guard h > v else { return }
                swipeState.onDragChanged(width: value.translation.width)
            }
            .onEnded { _ in
                swipeState.onDragEnded(isPlaying: player.isPlaying, onExpand: onExpand)
            }
    }

    var dragOpacity: Double {
        1.0 - Double(abs(swipeState.dragOffset)) / 200.0
    }
}

/// Checks the vibe engine for the mini player.
struct MiniVibeRelay: ViewModifier {
    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content.task(id: player.currentTrack?.id) {
            await player.checkVibeAvailability(client: env.client)
        }
    }
}
