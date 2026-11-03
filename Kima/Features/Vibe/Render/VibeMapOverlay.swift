import SwiftUI

/// The open band of the screen between the search list and the bottom stack (a panel, the readout or
/// the help line), minus the right-side rail, in screen points. A map label shows only inside it, so
/// no label draws through text or behind the rail's buttons.
struct VibeLabelBand: Equatable {
    var top: CGFloat = -.infinity
    var bottom: CGFloat = .infinity
    /// The rail's buttons and their labels; nil when it is not on screen.
    var rail: CGRect? = nil

    /// Half a label's height, padding included.
    static let labelHalfHeight: CGFloat = 10
    /// Clear space kept between a label and the rail.
    static let railGap: CGFloat = 8

    /// The band's top: below the top bar and mood chips (`hudBottom`), and below the search list
    /// while it is open. Both are global y values; nil when not measured or not on screen.
    static func top(hudBottom: CGFloat?, searchListBottom: CGFloat?) -> CGFloat {
        max(hudBottom.map { $0 + KimaSpacing.sm } ?? -.infinity,
            searchListBottom.map { $0 + KimaSpacing.xl } ?? -.infinity)
    }

    /// Whether a label centred at `y` sits fully inside the band.
    func holds(y: CGFloat) -> Bool {
        y - Self.labelHalfHeight >= top && y + Self.labelHalfHeight <= bottom
    }

    /// Whether a label of `size` centred at `centre` sits inside the band and clear of the rail.
    func holds(centre: CGPoint, size: CGSize) -> Bool {
        guard holds(y: centre.y) else { return false }
        guard let rail else { return true }
        let box = CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
                         width: size.width, height: size.height)
        return !box.intersects(rail.insetBy(dx: -Self.railGap, dy: -Self.railGap))
    }
}

/// The text and marks drawn over the Metal map: mood names, "start" and "end" over the song path's
/// rings, and the hairline from the selected star to its readout. Reads screen positions from
/// `VibeProjection`.
struct VibeMapOverlay: View {
    let projection: VibeProjection
    let selectedId: String?
    /// Where the leader ends; nil hides it.
    let leader: VibeLeaderTarget?
    let highlightedIds: [String]
    /// The song path's ends while its panel is open.
    let pathStartId: String?
    let pathEndId: String?
    /// Where labels may show; outside it the search list or the bottom stack is in the way.
    let labelBand: VibeLabelBand

    @AppStorage(VibeMapPrefs.showLabelsKey) private var showLabels = VibeMapPrefs.showLabelsDefault

    private var labelsShown: Bool {
        showLabels && projection.isOverview && selectedId == nil && highlightedIds.isEmpty
    }

    var body: some View {
        ZStack {
            ForEach(projection.labels) { label in
                moodLabel(label)
            }
            pathEndLabel("start", id: pathStartId)
            if pathEndId != pathStartId { pathEndLabel("end", id: pathEndId) }
            leaderLine
        }
        .allowsHitTesting(false)
    }

    // MARK: Mood labels

    @ViewBuilder private func moodLabel(_ label: VibeProjection.Label) -> some View {
        let on = labelsShown && label.visible
            && labelBand.holds(centre: label.centre, size: VibeProjection.labelSize(label.text))
        mapTag(label.text)
            .position(label.centre)
            .opacity(on ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: on)
            .accessibilityHidden(!on)
            .accessibilityIdentifier("vibe-anchor")
    }

    /// A label on the map: small text on the ink wash in a hairline capsule.
    private func mapTag(_ text: String) -> some View {
        Text(text)
            .font(KimaType.fitted(VibeProjection.labelFontSize))
            .tracking(VibeProjection.labelTracking)
            .foregroundStyle(KimaColor.textSecondary)
            .padding(.horizontal, VibeProjection.labelPadX)
            .padding(.vertical, VibeProjection.labelPadY)
            .background(Capsule().fill(KimaColor.vibeInkWash))
            .overlay(Capsule().strokeBorder(KimaColor.hairline, lineWidth: 1))
            .fixedSize()
    }

    // MARK: Song path ends

    /// "start" or "end" just above that end's ring, or just below it when above leaves the open band.
    @ViewBuilder private func pathEndLabel(_ text: String, id: String?) -> some View {
        if let id, let m = projection.markers[id], m.inFront {
            let size = VibeProjection.labelSize(text)
            let offset = CGFloat(VibeMapStyle.ringPathEnd.gap) + KimaSpacing.xs + size.height / 2
            let above = CGPoint(x: m.centre.x, y: m.centre.y - offset)
            let below = CGPoint(x: m.centre.x, y: m.centre.y + offset)
            if let centre = [above, below].first(where: { labelBand.holds(centre: $0, size: size) }) {
                mapTag(text)
                    .position(centre)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Leader

    /// A hairline from the selected star's ring down to the readout's top edge, elbowed around the rail.
    @ViewBuilder private var leaderLine: some View {
        if let id = selectedId, let target = leader, let m = projection.markers[id], m.inFront,
           let points = VibeLeader.points(star: m.centre, ringRadius: CGFloat(VibeMapStyle.ringSelectedAmber.gap),
                                          target: target) {
            Path { $0.addLines(points) }
                .stroke(KimaColor.vibeLeader, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                .accessibilityHidden(true)
        }
    }
}
