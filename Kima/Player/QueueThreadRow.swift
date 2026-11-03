import SwiftUI

// MARK: - QueueThreadRow

/// The mood-thread gutter beside each `QueueSheet` row: a vertical thread through a node at this track's position,
/// coloured by its map colour (or `env.accent.color` when none). One 3-stop gradient covers both segments with the
/// midpoint at this node's colour, so rows meet seamlessly; first/last rows fade at the open end. The current node
/// breathes; "played" dimming comes from `QueueSheet`'s row-wide `.opacity`.
struct QueueThreadRow: View {
    let nodeColor: Color
    let topNeighborColor: Color?
    let bottomNeighborColor: Color?
    let isCurrent: Bool
    let isPlaying: Bool

    @State private var breathe = false

    // MARK: - Tuning constants

    private let threadWidth: CGFloat = 1.75
    private let restingNodeDiameter: CGFloat = 6
    private let currentNodeDiameter: CGFloat = 13
    private let haloDiameter: CGFloat = 24
    private let threadOpacity: Double = 0.85
    private let gutterWidth: CGFloat = 28

    private var nodeDiameter: CGFloat { isCurrent ? currentNodeDiameter : restingNodeDiameter }

    // MARK: - Body

    var body: some View {
        ZStack {
            thread
            if isCurrent { halo }
            node
        }
        .frame(width: gutterWidth)
        .frame(maxHeight: .infinity)
        .onAppear { updateBreathing() }
        .onChange(of: isPlaying) { _, _ in updateBreathing() }
    }

    // MARK: - Layers

    /// Full-bleed vertical gradient. Stretches to the row's total height (including
    /// the vertical padding baked into the title/artist column) because `QueueSheet`
    /// keeps this view OUTSIDE that padding — see the `queueRow` layout comment.
    private var thread: some View {
        LinearGradient(
            stops: [
                .init(color: topNeighborColor ?? nodeColor.opacity(0), location: 0),
                .init(color: nodeColor, location: 0.5),
                .init(color: bottomNeighborColor ?? nodeColor.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: threadWidth)
        .opacity(threadOpacity)
    }

    private var halo: some View {
        Circle()
            .fill(nodeColor)
            .frame(width: haloDiameter, height: haloDiameter)
            .blur(radius: 5)
            .opacity(breathe ? 0.75 : 0.4)
    }

    private var node: some View {
        Circle()
            .fill(nodeColor)
            .frame(width: nodeDiameter, height: nodeDiameter)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
    }

    // MARK: - Breathing pulse (current + playing only)

    /// Starts (or gently settles) the halo's infinite breathe animation. Only ever
    /// runs on the current row — at most one `QueueThreadRow` qualifies at a time.
    private func updateBreathing() {
        guard isCurrent, isPlaying else {
            withAnimation(.easeOut(duration: 0.3)) { breathe = false }
            return
        }
        withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
            breathe = true
        }
    }
}
