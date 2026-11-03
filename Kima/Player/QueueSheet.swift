import SwiftUI

// MARK: - QueueSheet

/// Up-next queue sheet, presented from FullPlayerView's queue button, shown in play order (`playOrder`: shuffle order under shuffle).
/// A leading thread + node gutter (`QueueThreadRow`): node colour is the vibe-map colour, else `env.accent.color`.
/// Current track: largest, brightest node, accent text. Played tracks dim to 0.45 opacity; upcoming rows
/// drag-to-reorder by a handle after tapping edit. Tapping a row calls `player.jumpTo(index:)` (loads and auto-plays); scrolls to current on appear.
struct QueueSheet: View {

    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var editing = false
    /// Set the first time edit is tapped; the rows then stay built for the rest of the sheet (see `trackList`).
    @State private var hasEdited = false
    /// The longest queue whose rows are all built while editing.
    private static let editEagerLimit = 400
    /// The upcoming row being dragged by its handle, if any.
    @State private var drag: QueueDrag?
    @State private var scrollPosition = ScrollPosition()
    /// The scroll view's geometry, kept current without redrawing anything.
    @State private var latestScroll = QueueScrollBox()
    /// The scroll view's geometry while a row is held; the rows read it to slide. Left alone otherwise, so scrolling
    /// redraws nothing.
    @State private var scrollGeometry = QueueScrollGeometry()
    /// Every queue row is the same height; reordering steps by it.
    @State private var rowHeight: CGFloat = 56

    // MARK: - Helpers

    /// Number of tracks queued after the current one.
    private var upcomingCount: Int {
        max(0, player.playOrder.count - player.playPosition - 1)
    }

    /// True when playback stops after the current song: nothing upcoming and repeat off.
    private var endsAfterCurrent: Bool {
        upcomingCount == 0 && player.repeatMode == .off && !player.playbackType.isLongForm
    }

    /// Clamped currentIndex — safe to subscript `queue` with.
    private var safeCurrentIndex: Int {
        max(0, min(player.currentIndex, player.queue.count - 1))
    }

    /// Queue index at a play-order position, nil past either end.
    private func queueIndex(atPlayPosition pos: Int) -> Int? {
        let order = player.playOrder
        return order.indices.contains(pos) ? order[pos] : nil
    }

    // MARK: - Thread node colour

    /// This track's thread-node colour: its mood blend, or `env.accent.color` when it has no mood
    /// data. The current track mirrors `env.accent`.
    private func nodeColor(for track: Track, isCurrent: Bool) -> Color {
        if isCurrent { return env.accent.color }
        if let c = env.vibeMapViewModel.colour(for: track.id) { return KimaBrandGradient.color(at: c) }
        return env.accent.color
    }

    /// Neighbour lookup by play-order position. Returns nil past either end of the
    /// queue so `QueueThreadRow` can fade its thread to transparent at the open end
    /// instead of implying a neighbour that doesn't exist.
    private func nodeColor(atPlayPosition pos: Int) -> Color? {
        guard let idx = queueIndex(atPlayPosition: pos), player.queue.indices.contains(idx) else { return nil }
        return nodeColor(for: player.queue[idx], isCurrent: idx == safeCurrentIndex)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            KimaHairline()
                .padding(.horizontal, KimaSpacing.lg)

            if player.queue.isEmpty {
                emptyState
            } else {
                trackList
            }
        }
        .background(KimaColor.surfaceRaised.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.sm) {
            Text("up next")
                .font(KimaType.pageTitle)
                .foregroundStyle(KimaColor.textPrimary)
                .tracking(-0.4)
                // Accessibility marker for the queue, placed on the content because a sheet never exposes
                // a root-placed identifier.
                .accessibilityIdentifier("queue-sheet-up-next")

            Spacer()

            if !player.queue.isEmpty {
                Text(player.queueOrigin?.header(trackCount: player.queue.count)
                     ?? "\(player.queue.count) track\(player.queue.count == 1 ? "" : "s")")
                    .font(KimaType.meta.monospacedDigit())
                    .accessibilityIdentifier("queue-sheet-origin")
                    .foregroundStyle(KimaColor.textMuted)
            }

            // EDIT appears only when there is something upcoming; CLEAR lives at the end of the list.
            if upcomingCount > 0 {
                Button {
                    hasEdited = true
                    withAnimation { editing.toggle() }
                } label: {
                    Text(editing ? "done" : "edit")
                        .font(KimaType.meta)
                        .foregroundStyle(editing ? KimaColor.textPrimary : KimaColor.textMuted)
                        .kimaHitTarget()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.top, KimaSpacing.lg)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        KimaEmptyState(icon: "music.note.list", title: "queue is empty", message: nil)
    }

    // MARK: - Track list

    /// Rows are built when the sheet opens (`KimaPageStack`), so scrolling builds nothing.
    private var trackList: some View {
        let order = player.playOrder
        let cur = max(0, min(player.playPosition, order.count - 1))

        return ScrollViewReader { proxy in
            ScrollView {
                // From the first edit on every row stays built, so a row held during auto-scroll is never let go of
                // (and "done" does not rebuild the list); a queue too long to build at once stays lazy, and a held row
                // that scrolls far away drops unmoved.
                KimaPageStack(count: order.count, allEager: hasEdited && order.count <= Self.editEagerLimit) {
                    // Played tracks + current track (in play order) — not movable.
                    if cur > 0 { QueueSectionLabel(title: "played") }
                    ForEach(Array(order[0...cur].enumerated()), id: \.offset) { playPos, queueIdx in
                        queueRow(
                            track: player.queue[queueIdx], queueIndex: queueIdx, playPos: playPos,
                            isCurrent: playPos == cur, isPlayed: playPos < cur
                        )
                    }

                    // Upcoming tracks — drag-to-reorder by the handle while editing.
                    if cur + 1 < order.count {
                        ForEach(Array(order[(cur + 1)...].enumerated()), id: \.offset) { localIdx, queueIdx in
                            let playPos = cur + 1 + localIdx
                            queueRow(
                                track: player.queue[queueIdx], queueIndex: queueIdx, playPos: playPos,
                                isCurrent: false, isPlayed: false
                            )
                            .modifier(QueueReorderRow(
                                playPos: playPos, firstMovable: cur + 1, lastMovable: order.count - 1,
                                editing: editing, drag: $drag, scroll: scrollGeometry, rowHeight: rowHeight,
                                begin: { from, fingerY in
                                    scrollGeometry = latestScroll.geometry
                                    drag = QueueDrag(from: from, startFingerY: fingerY,
                                                     startScrollY: latestScroll.geometry.y, fingerY: fingerY)
                                },
                                move: { from, to in
                                    player.moveInQueue(fromPlayPositions: [from], toPlayPosition: to > from ? to + 1 : to)
                                }
                            ))
                        }

                        clearUpcomingRow
                    } else if endsAfterCurrent {
                        QueueEndRow()
                    }
                }
            }
            .scrollPosition($scrollPosition)
            .coordinateSpace(.named(QueueReorderRow.viewport))
            .onScrollGeometryChange(for: QueueScrollGeometry.self) { QueueScrollGeometry($0) } action: { _, new in
                latestScroll.geometry = new
                if drag != nil { scrollGeometry = new }
            }
            .task(id: drag != nil) { await autoScroll() }
            // A held row lets go when the rows under it change.
            .onChange(of: player.playPosition) { drag = nil }
            .onChange(of: order.count) { drag = nil }
            .onChange(of: editing) { drag = nil }
            // Leave edit mode when the queue drains to the now-playing track.
            .onChange(of: upcomingCount) { _, count in
                if count == 0 { editing = false }
            }
            .onAppear {
                proxy.scrollTo(max(0, player.playPosition - 1), anchor: .top)
            }
            .onChange(of: player.playPosition) { _, pos in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(max(0, pos - 1), anchor: .top)
                }
            }
        }
    }

    /// While a row is held near the top or bottom edge, scrolls the queue toward it, faster the closer the finger is.
    private func autoScroll() async {
        let edge: CGFloat = 48, top: CGFloat = 14
        while !Task.isCancelled, let held = drag {
            let g = latestScroll.geometry
            var step: CGFloat = 0
            if held.fingerY < edge { step = -top * min(1, (edge - held.fingerY) / edge) }
            else if held.fingerY > g.viewport - edge { step = top * min(1, (held.fingerY - (g.viewport - edge)) / edge) }
            if step != 0 {
                scrollPosition.scrollTo(y: min(max(g.minY, g.y + step), g.maxY))
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    // MARK: - Clear upcoming

    /// Clears the local queue only. It sits apart at the end of the list (never beside edit) and always confirms.
    private var clearUpcomingRow: some View {
        let plural = upcomingCount == 1 ? "" : "s"
        return KimaDestructiveRow(
            label: "clear upcoming",
            confirmTitle: "clear upcoming tracks?",
            confirmMessage: "removes \(upcomingCount) upcoming track\(plural) from the queue.",
            confirmButton: "remove \(upcomingCount) track\(plural)"
        ) {
            player.clearUpcoming()
            editing = false
        }
        .padding(.bottom, KimaSpacing.lg)
    }

    // MARK: - Queue row

    @ViewBuilder
    private func queueRow(
        track: Track,
        queueIndex: Int,
        playPos: Int,
        isCurrent: Bool,
        isPlayed: Bool
    ) -> some View {
        Button {
            guard !editing else { return }
            player.jumpTo(index: queueIndex)
            dismiss()
        } label: {
            // The thread gutter sits outside the row's vertical padding so it spans the full row height;
            // rows sit edge to edge, so neighbouring threads join into one continuous line.
            HStack(spacing: 0) {
                QueueThreadRow(
                    nodeColor: nodeColor(for: track, isCurrent: isCurrent),
                    topNeighborColor: nodeColor(atPlayPosition: playPos - 1),
                    bottomNeighborColor: nodeColor(atPlayPosition: playPos + 1),
                    isCurrent: isCurrent,
                    isPlaying: player.isPlaying
                )

                HStack(spacing: KimaSpacing.md) {
                    // Cover sleeve — the web queue is cover-art-led. The thread node
                    // still carries the vibe arc; the sleeve answers "which track" at a glance.
                    AlbumSleeveThumbnail(
                        coverId: track.album?.coverArt,
                        size: 40,
                        cornerRadius: KimaRadius.image,
                        shadowRadius: 4,
                        shadowOpacity: 0.35,
                        shadowY: 2,
                        animationId: AnyHashable(track.id)
                    )

                    // Title + artist
                    VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                        Text(track.effectiveTitle.lowercased())
                            .font(KimaType.captionStrong)
                            .foregroundStyle(isCurrent ? env.accent.color : KimaColor.textPrimary)
                            .lineLimit(1)

                        if let artist = track.artist?.name {
                            Text(artist.lowercased())
                                .font(KimaType.caption)
                                .foregroundStyle(KimaColor.textMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    // Duration in mono
                    Text(track.duration.durationFormatted)
                        .font(KimaType.caption.monospacedDigit())
                        .foregroundStyle(KimaColor.textMuted)
                }
                .padding(.vertical, KimaSpacing.sm)
                // Divider under the row, starting at the title like a list separator.
                .overlay(alignment: .bottom) {
                    Rectangle().fill(KimaColor.hairline).frame(height: 1 / displayScale)
                        .padding(.leading, 40 + KimaSpacing.md)
                }
                .padding(.trailing, KimaSpacing.lg)
            }
            .padding(.leading, KimaSpacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Played tracks are dimmed (thread + node included); current + upcoming
        // at full opacity.
        .opacity(isPlayed ? 0.45 : 1.0)
        // Reordering steps by the first upcoming row's height; every upcoming row has the same layout.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if playPos == player.playPosition + 1 { rowHeight = $0 } }
        .id(playPos)
    }
}

extension View {
    /// The queue sheet with its shared presentation style (full player and shell deep-link both use it).
    func queueSheet(isPresented: Binding<Bool>, env: AppEnvironment, toastCenter: ToastCenter) -> some View {
        modifier(QueueSheetPresenter(isPresented: isPresented, env: env, toastCenter: toastCenter))
    }
}

/// Half or full height on iPhone. On iPad a page-sized sheet at full height, so the queue shows more than a
/// handful of tracks. The width class is read here, on the presenting side.
private struct QueueSheetPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let env: AppEnvironment
    let toastCenter: ToastCenter
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            QueueSheet()
                .appEnvironment(env, toastCenter)
                .presentationDetents(sizeClass == .regular ? [.large] : [.medium, .large])
                .presentationSizing(.page)
                .presentationDragIndicator(.visible)
                .presentationBackground(KimaColor.surfaceRaised)
        }
    }
}
