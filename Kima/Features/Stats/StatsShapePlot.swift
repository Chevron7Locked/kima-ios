import SwiftUI

// MARK: Brightness and energy plot

struct StatsShape: View {
    let l: ListeningStats
    let period: StatsPeriod

    @Environment(AppEnvironment.self) private var env
    @State private var probe: StatsShapeMath.Probe?
    @State private var answered: (probe: StatsShapeMath.Probe, region: RegionDetail?)?
    @State private var fetch: Task<Void, Never>?
    @State private var selectedMonth: Int?
    @State private var side: CGFloat = 0

    private typealias M = StatsShapeMath
    /// The plot and its captions sit this far in from the leading edge, clear of the energy axis label.
    private static let plotInset: CGFloat = 60

    private struct Month { let month: String; let energy: Double; let valence: Double; let plays: Int; let bpm: Double? }

    private var shape: [(x: Int, y: Int, plays: Int)] { l.shape.map { ($0.x, $0.y, $0.plays) } }
    private var maxPlays: Int { shape.map(\.plays).max() ?? 0 }
    private var path: [Month] {
        l.drift.compactMap { d in
            guard let e = d.energy, let v = d.valence else { return nil }
            return Month(month: d.month, energy: e, valence: v, plays: d.plays, bpm: d.bpm)
        }
    }
    private var maxMonth: Int { max(1, path.map(\.plays).max() ?? 1) }

    private func playsWord(_ n: Int) -> String { n == 1 ? "1 play" : "\(n) plays" }

    var body: some View {
        let path = self.path
        let active = selectedMonth ?? (path.count - 1)
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            StatsFinding(claim: "brightness & energy",
                         note: "plays by brightness (across) and energy (up)")
            if maxPlays == 0 {
                Text("needs audio analysis")
                    .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
            } else {
                plot(path: path, active: active)
                HStack {
                    Text("dark"); Spacer(); Text("bright")
                }
                .font(KimaType.caption).foregroundStyle(KimaColor.textFaint)
                .padding(.leading, Self.plotInset)
                if path.count > 2 { monthStrip(path: path, active: active) }
                StatsShapeReadout(content: content(path: path), onClear: { setProbe(nil) })
                    .padding(.leading, Self.plotInset)
            }
        }
        .onChange(of: period) { setProbe(nil); selectedMonth = nil }
    }

    // MARK: plot

    private func plot(path: [Month], active: Int) -> some View {
        let maxPlays = self.maxPlays
        let maxMonth = self.maxMonth
        let cells = shape
        let probe = self.probe
        return Canvas { ctx, size in
            let s = size.width
            func pt(_ p: Double) -> CGFloat { CGFloat(p / 100) * s }
            func pos(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: pt(x), y: s - pt(y)) }

            ctx.stroke(Path(CGRect(x: 0, y: 0, width: s, height: s)), with: .color(KimaColor.hairline), lineWidth: 1)
            for q in [25.0, 50, 75] {
                var line = Path()
                line.move(to: CGPoint(x: pt(q), y: 0)); line.addLine(to: CGPoint(x: pt(q), y: s))
                line.move(to: CGPoint(x: 0, y: pt(q))); line.addLine(to: CGPoint(x: s, y: pt(q)))
                ctx.stroke(line, with: .color(Color.white.opacity(0.05)), lineWidth: 0.5)
            }
            for c in cells where c.plays > 0 {
                let r = pt(M.dotRadius(plays: c.plays, max: maxPlays))
                let p = pos(M.cellCentre(c.x), M.cellCentre(c.y))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(KimaColor.brand.opacity(M.dotOpacity(plays: c.plays, max: maxPlays))))
            }
            if let probe {
                let half = (100 - 2 * M.pad) / 24 / 2
                let x0 = M.cellCentre(probe.x - 1) - half, x1 = M.cellCentre(probe.x + 1) + half
                let y0 = M.cellCentre(probe.y - 1) - half, y1 = M.cellCentre(probe.y + 1) + half
                let rect = CGRect(x: pt(x0), y: s - pt(y1), width: pt(x1 - x0), height: pt(y1 - y0))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.white.opacity(0.55)), lineWidth: 1)
            }
            if path.count > 1 {
                for (i, m) in path.enumerated() where i != active {
                    let age = Double(i) / Double(path.count - 1)
                    let w = (Double(m.plays) / Double(maxMonth)).squareRoot()
                    let r = pt(1 + w * 1.6)
                    let p = pos(M.onScale(m.valence), M.onScale(m.energy))
                    let circle = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                    ctx.stroke(circle, with: .color(Color.black.opacity(0.85)), lineWidth: 0.016 * s)
                    ctx.fill(circle, with: .color(Color(white: 0.96).opacity(0.2 + 0.62 * age)))
                }
                if path.indices.contains(active) {
                    let m = path[active]
                    let p = pos(M.onScale(m.valence), M.onScale(m.energy))
                    func disc(_ r: CGFloat) -> Path {
                        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                    }
                    ctx.stroke(disc(0.03 * s), with: .color(Color.black), lineWidth: 0.024 * s)
                    ctx.stroke(disc(0.03 * s), with: .color(Color.white), lineWidth: 0.01 * s)
                    ctx.fill(disc(0.01 * s), with: .color(Color.white))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { v in
            guard side > 0 else { return }
            let p = M.Probe(x: M.bucketAt(v.location.x / side * 100),
                            y: M.bucketAt(100 - v.location.y / side * 100))
            setProbe(p == self.probe ? nil : p)
        })
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { side = $0 }
        .accessibilityElement()
        .accessibilityLabel("brightness and energy plot")
        .accessibilityValue(idleHeadline(path: path))
        .accessibilityIdentifier("shape-plot")
        .padding(.leading, Self.plotInset)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("high energy")
                Spacer(minLength: 0)
                Text("low energy")
            }
            .font(KimaType.caption)
            .foregroundStyle(KimaColor.textFaint)
            .multilineTextAlignment(.trailing)
            .frame(width: 52)
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: month strip

    private func monthStrip(path: [Month], active: Int) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            Text("plays per month")
                .font(KimaType.caption).foregroundStyle(KimaColor.textFaint)
                .padding(.leading, Self.plotInset)
            HStack(alignment: .bottom, spacing: 3) {  // chart geometry: gap between bars/cells
                ForEach(path.indices, id: \.self) { i in
                    let m = path[i]
                    Button { selectedMonth = (selectedMonth == i) ? nil : i } label: {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle()
                                .fill(i == active ? Color(white: 0.96) : KimaColor.brand.opacity(0.45))
                                .frame(height: max(0.06, Double(m.plays) / Double(maxMonth)) * 48)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(M.monthShort(m.month)), \(playsWord(m.plays))")
                    .accessibilityIdentifier("shape-month-\(m.month)")
                }
            }
            .frame(height: 48)
            .padding(.leading, Self.plotInset)
        }
    }

    // MARK: readout content

    private func idleHeadline(path: [Month]) -> String {
        if let i = selectedMonth, path.indices.contains(i) {
            let m = path[i]
            return "\(M.monthLong(m.month)): \(M.energyWord(m.energy)), \(M.brightnessWord(m.valence))"
        }
        return M.overall(shape).map { "average: \(M.energyWord($0.energy)), \(M.brightnessWord($0.valence))" } ?? ""
    }

    private func idleContent(path: [Month]) -> StatsShapeReadout.Content {
        if let i = selectedMonth, path.indices.contains(i) {
            let m = path[i]
            let body = playsWord(m.plays) + (m.bpm.map { " · avg \(Int($0.rounded())) bpm" } ?? "")
            return .idle(headline: idleHeadline(path: path), body: body, meta: ["tap to see tracks"])
        }
        var meta: [String] = []
        if let b = M.barest(shape) { meta.append("least played: \(b.name) (\(b.percent)%)") }
        meta.append("tap to see tracks")
        return .idle(headline: idleHeadline(path: path),
                     body: M.movement(path.map { ($0.month, $0.energy, $0.valence) }),
                     meta: meta)
    }

    private func content(path: [Month]) -> StatsShapeReadout.Content {
        guard let probe else { return idleContent(path: path) }
        guard let a = answered, a.probe == probe else { return .loading }
        if let r = a.region, r.listens > 0 { return .region(r) }
        return idleContent(path: path)
    }

    private func setProbe(_ p: StatsShapeMath.Probe?) {
        probe = p
        fetch?.cancel()
        answered = nil
        guard let p else { return }
        fetch = Task {
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }
            let r = try? await env.client.getRegionDetail(x: p.x, y: p.y, period: period)
            if Task.isCancelled || probe != p { return }
            answered = (p, r)
        }
    }
}
