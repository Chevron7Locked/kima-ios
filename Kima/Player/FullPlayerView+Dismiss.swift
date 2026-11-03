import SwiftUI

// MARK: - Dismiss gesture
// Pull-to-dismiss: drag down past the threshold dismisses, otherwise a spring settles the sheet back.
// The state (`dismissDelta`, `dismissThreshold`) stays in the main struct.

extension FullPlayerView {

    // MARK: - Dismiss gesture

    var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard value.translation.height > 0,
                      value.translation.height > abs(value.translation.width) * 1.2
                else { return }
                dismissDelta = value.translation.height
            }
            .onEnded { _ in
                if dismissDelta > dismissThreshold {
                    dismiss()
                } else {
                    withAnimation(.spring(duration: 0.38, bounce: 0.25)) {
                        dismissDelta = 0
                    }
                }
            }
    }
}
