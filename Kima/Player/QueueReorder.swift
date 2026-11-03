import SwiftUI

/// The upcoming row held by its reorder handle: its play position and where the finger is, in the queue's viewport.
struct QueueDrag: Equatable {
    let from: Int
    let startFingerY: CGFloat
    let startScrollY: CGFloat
    var fingerY: CGFloat
}

/// Holds the latest `QueueScrollGeometry`; a class, so updating it on every scroll frame redraws nothing.
final class QueueScrollBox {
    var geometry = QueueScrollGeometry()
}

/// The queue scroll view's offset, its scrollable range and its visible height.
struct QueueScrollGeometry: Equatable {
    var y: CGFloat = 0
    var minY: CGFloat = 0
    var maxY: CGFloat = 0
    var viewport: CGFloat = 0

    init() {}

    init(_ g: ScrollGeometry) {
        y = g.contentOffset.y
        minY = -g.contentInsets.top
        maxY = max(minY, g.contentSize.height - g.containerSize.height + g.contentInsets.bottom)
        viewport = g.containerSize.height
    }
}

/// One upcoming queue row while reordering. Editing shows a handle at the trailing edge; dragging it lifts the row,
/// slides the rows it passes out of the way, and on release moves the track to the slot it was dropped on. Rows
/// between `firstMovable` and `lastMovable` (play positions) are the only slots.
struct QueueReorderRow: ViewModifier {
    static let viewport = "queue-viewport"

    let playPos: Int
    let firstMovable: Int
    let lastMovable: Int
    let editing: Bool
    @Binding var drag: QueueDrag?
    let scroll: QueueScrollGeometry
    let rowHeight: CGFloat
    /// Picks this row up: its play position and the finger's height in the viewport.
    let begin: (Int, CGFloat) -> Void
    /// Moves the track at the first play position to the second.
    let move: (Int, Int) -> Void

    /// True while the finger is on this row's handle; resets even when the system cancels the drag.
    @GestureState private var pressing = false

    private var lifted: Bool { drag?.from == playPos }

    /// How far the held row has travelled, finger movement plus any scrolling since it was picked up.
    private var travel: CGFloat {
        guard let drag else { return 0 }
        return drag.fingerY - drag.startFingerY + scroll.y - drag.startScrollY
    }

    /// The play position the held row would drop on now.
    private var target: Int? {
        guard let drag, rowHeight > 0 else { return nil }
        return min(max(drag.from + Int((travel / rowHeight).rounded()), firstMovable), lastMovable)
    }

    /// How far this row slides to make room for the held one.
    private var shift: CGFloat {
        guard let drag, let target, !lifted else { return 0 }
        if drag.from < playPos, playPos <= target { return -rowHeight }
        if target <= playPos, playPos < drag.from { return rowHeight }
        return 0
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if editing {
                    handle.transition(.opacity)
                }
            }
            .background { if lifted { KimaColor.surfaceRaised } }
            .scaleEffect(lifted ? 1.02 : 1)
            .offset(y: lifted ? travel : shift)
            .zIndex(lifted ? 1 : 0)
            .animation(.easeOut(duration: 0.18), value: shift)
            .animation(.easeOut(duration: 0.18), value: lifted)
            .accessibilityActions {
                if editing {
                    if playPos > firstMovable { Button("move up") { move(playPos, playPos - 1) } }
                    if playPos < lastMovable { Button("move down") { move(playPos, playPos + 1) } }
                }
            }
    }

    private var handle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(KimaColor.textMuted)
            .frame(width: 44, height: 44)
            .background(KimaColor.surfaceRaised)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.viewport))
                    .updating($pressing) { _, state, _ in state = true }
                    .onChanged { value in
                        if drag == nil { begin(playPos, value.startLocation.y) }
                        drag?.fingerY = value.location.y
                    }
                    .onEnded { _ in
                        let to = target
                        var instant = Transaction()
                        instant.disablesAnimations = true
                        withTransaction(instant) {
                            if let to, to != playPos { move(playPos, to) }
                            drag = nil
                        }
                    }
            )
            // A drag the system cancels, or a row that leaves the screen mid-drag, lets go without moving.
            .onChange(of: pressing) { _, down in
                if !down, lifted { drag = nil }
            }
            .onDisappear { if lifted { drag = nil } }
            .padding(.trailing, KimaSpacing.sm)
            .accessibilityHidden(true)
    }
}
