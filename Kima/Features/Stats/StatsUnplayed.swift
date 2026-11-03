import SwiftUI

// MARK: Unplayed (coverage fractions + decades + "shuffle 40 unplayed")

struct StatsUnplayed: View {
    let shelf: ShelfStats
    let period: StatsPeriod
    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @State private var shuffling = false

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            StatsFinding(claim: "\(shelf.neverPlayed.formatted(.number)) \(shelf.neverPlayed == 1 ? "track" : "tracks") never played",
                         scope: period == .all ? nil : "all time")
            CoverageGrid(shelf: shelf)
            if shelf.neverPlayed > 0 {
                Button {
                    shuffling = true
                    Task {
                        defer { shuffling = false }
                        guard let tracks = try? await env.client.getPlayableSlice(of: "never", limit: 40, period: period),
                              !tracks.isEmpty else { return }
                        player.play(tracks: tracks)
                    }
                } label: {
                    HStack(spacing: KimaSpacing.sm) {
                        if shuffling { ProgressView().controlSize(.small) }
                        Label("shuffle 40 unplayed", systemImage: "shuffle")
                    }
                    .font(KimaType.headline)
                    .foregroundStyle(KimaColor.textPrimary)
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.vertical, KimaSpacing.md)
                    .background(KimaColor.surfaceRaised, in: RoundedRectangle(cornerRadius: KimaRadius.card))
                }
                .buttonStyle(.plain)
                .disabled(shuffling)
                .accessibilityIdentifier("shuffle-unplayed")
            }
            StatsDecades(decades: shelf.decades)
        }
    }
}

private struct CoverageGrid: View {
    let shelf: ShelfStats

    var body: some View {
        let rows: [(String, Int, Int)] = [
            ("tracks played", shelf.tracks.heard, shelf.tracks.total),
            ("albums played", shelf.albums.heard, shelf.albums.total),
            ("artists played", shelf.artists.heard, shelf.artists.total),
            ("tracks analysed", shelf.analysis.done, shelf.analysis.total),
        ]
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: KimaSpacing.xl) {
            ForEach(rows, id: \.0) { row in
                let pct = StatsFormat.percent(part: row.1, whole: row.2)
                VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                    Text("\(pct)%")
                        .font(KimaType.figure)
                        .foregroundStyle(KimaColor.textPrimary)
                        .monospacedDigit()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(KimaColor.hairline).frame(height: 2)
                            Rectangle().fill(KimaColor.brand)
                                .frame(width: geo.size.width * CGFloat(pct) / 100, height: 2)
                        }
                    }
                    .frame(height: 2)
                    VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                        Text(row.0)
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textSecondary)
                        Text("\(row.1.formatted(.number)) of \(row.2.formatted(.number))")
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textMuted)
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

private struct StatsDecades: View {
    let decades: [DecadeRow]
    @State private var selectedDecade: Int?
    @State private var width: CGFloat = 0

    private typealias Math = StatsShelfMath

    /// Disc geometry shared by the canvas and the tap handler so they agree on x.
    private func layout(count: Int, width: CGFloat) -> (maxR: CGFloat, step: CGFloat) {
        let gaps = CGFloat(max(1, count - 1))
        let maxR = min(22, (width / (2 * (gaps + 1))) * 0.92)
        return (maxR, (width - maxR * 2) / gaps)
    }

    var body: some View {
        // Decade discs sized by albums owned, filled by albums played.
        let shown = decades.filter { $0.albums > 0 }
        if shown.count > 1 {
            let maxAlbums = max(1, shown.map(\.albums).max() ?? 1)
            let geo = layout(count: shown.count, width: width)
            let centres = shown.indices.map { Double(geo.maxR + CGFloat($0) * geo.step) }
            let summary = Math.decadeSummary(shown.map { (decade: $0.decade, albums: $0.albums, heard: $0.heard) })
            VStack(alignment: .leading, spacing: KimaSpacing.md) {
                if let summary {
                    Text(Math.decadeSentence(biggest: summary.biggest, coldest: summary.coldest))
                        .font(KimaType.body)
                        .foregroundStyle(KimaColor.textSecondary)
                }
                Canvas { ctx, size in
                    let g = layout(count: shown.count, width: size.width)
                    let minR = min(7, g.maxR * 0.32)
                    for (i, d) in shown.enumerated() {
                        let r = (minR * minR + (Double(d.albums) / Double(maxAlbums)) * (g.maxR * g.maxR - minR * minR)).squareRoot()
                        let c = CGPoint(x: g.maxR + CGFloat(i) * g.step, y: 26)
                        let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                        ctx.fill(circle, with: .color(KimaColor.surfaceHover))
                        ctx.stroke(circle, with: .color(KimaColor.hairline), lineWidth: 1)
                        let fill = d.albums > 0 ? CGFloat(d.heard) / CGFloat(d.albums) : 0
                        if fill > 0 {
                            ctx.drawLayer { layer in
                                layer.clip(to: circle)
                                layer.fill(Path(CGRect(x: c.x - r, y: c.y + r - 2 * r * fill, width: r * 2, height: r * 2 * fill)),
                                           with: .color(KimaColor.brand))
                            }
                        }
                        if selectedDecade == d.decade {
                            ctx.stroke(circle, with: .color(Color.white), lineWidth: 1)
                        }
                        ctx.draw(Text(String(String(d.decade).suffix(2)))
                                    .font(KimaType.meta)
                                    .foregroundStyle(KimaColor.textMuted),
                                 at: CGPoint(x: c.x, y: 58))
                    }
                }
                .frame(height: 64)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    guard let i = Math.nearestIndex(x: Double(v.location.x), centres: centres) else { return }
                    let d = shown[i].decade
                    selectedDecade = (selectedDecade == d) ? nil : d
                })
                .accessibilityElement()
                .accessibilityLabel("albums by decade · most from the \(summary.map { Math.decadeLabel($0.biggest) } ?? "")")
                .accessibilityIdentifier("decades-plot")
                Text(readout(shown))
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textFaint)
                    .frame(height: 18, alignment: .leading)
                    .accessibilityIdentifier("decades-readout")
            }
        }
    }

    private func readout(_ shown: [DecadeRow]) -> String {
        guard let sel = selectedDecade, let d = shown.first(where: { $0.decade == sel }) else {
            return "size = albums owned · fill = albums played"
        }
        if d.albums == 0 { return "\(d.decade)s: no albums" }
        return "\(d.decade)s: \(d.heard) of \(d.albums) \(d.albums == 1 ? "album" : "albums") played"
    }
}
