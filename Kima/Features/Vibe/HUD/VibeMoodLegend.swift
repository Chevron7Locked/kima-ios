import SwiftUI

/// One scrolling row of mood chips under the top bar (colour dot, name, count), with the total track count on its
/// own line beneath. Tapping a chip pins that mood: full-strength text on a soft wash of the mood colour, with the
/// same neutral edge (amber stays the map's only "on" ring); tapping again unpins. The row fades at each edge so
/// a chip cut off at the right shows that the row scrolls.
struct VibeMoodLegend: View {
    let entries: [VibeLegendEntry]
    let pinned: String?
    let trackCount: Int
    let onToggle: (String) -> Void

    private static let leadFade: CGFloat = KimaSpacing.md
    private static let trailFade: CGFloat = KimaSpacing.xl

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KimaSpacing.sm) {
                    ForEach(entries) { entry in chip(entry) }
                }
                .padding(.leading, KimaSpacing.lg)
                .padding(.trailing, KimaSpacing.lg + Self.trailFade)
            }
            .mask(edgeFade)
            Text("\(trackCount.formatted()) tracks")
                .font(KimaType.meta)
                .monospacedDigit()
                .foregroundStyle(KimaColor.textMuted)
                .padding(.leading, KimaSpacing.lg)
                .accessibilityIdentifier("vibe-track-count")
        }
    }

    /// Opaque in the middle, fading to clear over the first and last few points.
    private var edgeFade: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: min(0.5, Self.leadFade / w)),
                .init(color: .black, location: max(0.5, 1 - Self.trailFade / w)),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        }
    }

    private func chip(_ entry: VibeLegendEntry) -> some View {
        let on = pinned == entry.key
        let dot = VibeMoodPalette.mapColor(for: entry.key)
        return Button { onToggle(entry.key) } label: {
            HStack(spacing: KimaSpacing.sm) {
                HStack(spacing: KimaSpacing.xs) {
                    Circle().fill(dot).frame(width: 6, height: 6)
                    Text(entry.label)
                }
                Text(entry.count.formatted()).monospacedDigit()
                    .foregroundStyle(on ? KimaColor.textSecondary : KimaColor.textMuted)
            }
            .font(KimaType.caption)
            // Unpinned chips use the web's 72% ink; the pinned one goes to full strength.
            .foregroundStyle(on ? KimaColor.textPrimary : KimaColor.textPrimary.opacity(0.72))
            .padding(.horizontal, KimaSpacing.md)
            .frame(minHeight: KimaSpacing.xxl)
            .background {
                Capsule().fill(KimaColor.vibeInkWash)
                    .overlay(Capsule().fill(dot.opacity(on ? 0.15 : 0)))
            }
            .kimaOutline(Capsule())
            .frame(minHeight: KimaLayout.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("\(entry.label), \(entry.count.formatted())")
        .accessibilityIdentifier("vibe-legend-chip")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
