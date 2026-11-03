import SwiftUI
import Charts

// MARK: Energy by hour (normalised curve + plays band, Swift Charts)

struct StatsEnergy: View {
    let s: Signature

    @State private var selectedHour: Int?

    private var rows: [StatsEnergyMath.Hour] {
        StatsEnergyMath.rows(s.hourly.map { (hour: $0.hour, plays: $0.plays, energy: $0.energy) })
    }

    var body: some View {
        let rows = rows
        if StatsEnergyMath.playedCount(rows) >= 3,
           let frantic = StatsEnergyMath.frantic(rows),
           let calmest = StatsEnergyMath.calmest(rows) {
            let norm = StatsEnergyMath.normalized(rows)
            VStack(alignment: .leading, spacing: KimaSpacing.md) {
                StatsFinding(claim: "highest energy: around \(StatsFormat.hourLabel(frantic))",
                             note: "average track energy of plays, by hour")
                Text(readout(rows))
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textSecondary)
                    .monospacedDigit()
                    .frame(height: 18, alignment: .leading)
                    .accessibilityIdentifier("energy-readout")
                HStack(alignment: .top, spacing: KimaSpacing.sm) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("high")
                        Spacer(minLength: 0)
                        Text("low")
                    }
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textFaint)
                    .frame(width: 40, height: 110)
                    curve(rows, norm: norm, frantic: frantic, calmest: calmest)
                }
                HStack(alignment: .top, spacing: KimaSpacing.sm) {
                    Text("plays")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textFaint)
                        .frame(width: 40, height: 32, alignment: .trailing)
                    band(rows)
                }
            }
            .onChange(of: s.hourly.count) { selectedHour = nil }
        }
    }

    private func readout(_ rows: [StatsEnergyMath.Hour]) -> String {
        guard let h = selectedHour, rows.indices.contains(h) else { return "" }
        let r = rows[h]
        guard r.plays > 0, let raw = r.raw else { return "\(StatsFormat.hourLabel(h)) · no plays" }
        let plays = r.plays == 1 ? "1 play" : "\(r.plays.formatted(.number)) plays"
        return "\(StatsFormat.hourLabel(h)) · energy \(Int((raw * 100).rounded())) · \(plays)"
    }

    private func curve(_ rows: [StatsEnergyMath.Hour], norm: [Double], frantic: Int, calmest: Int) -> some View {
        Chart {
            ForEach(rows) { r in
                LineMark(x: .value("hour", r.hour), y: .value("energy", norm[r.hour]))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .foregroundStyle(KimaColor.brand)
            }
            if let h = selectedHour {
                RuleMark(x: .value("hour", h))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("hour", h), y: .value("energy", norm[h]))
                    .foregroundStyle(Color.white)
                    .symbolSize(30)
            }
        }
        .chartXScale(domain: 0...23)
        .chartYScale(domain: -0.05...1.05)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 110)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { v in
                        guard let frame = proxy.plotFrame else { return }
                        let x = v.location.x - geo[frame].origin.x
                        guard let h = proxy.value(atX: x, as: Double.self)
                                ?? proxy.value(atX: x, as: Int.self).map(Double.init) else { return }
                        let hour = min(23, max(0, Int(h.rounded())))
                        selectedHour = (selectedHour == hour) ? nil : hour
                    })
            }
        }
        .accessibilityLabel("highest energy around \(StatsFormat.hourLabel(frantic)), lowest around \(StatsFormat.hourLabel(calmest))")
        .accessibilityIdentifier("energy-chart")
    }

    private func band(_ rows: [StatsEnergyMath.Hour]) -> some View {
        let maxPlays = rows.map(\.plays).max() ?? 1
        return Chart(rows) { r in
            AreaMark(x: .value("hour", r.hour), y: .value("plays", r.plays))
                .interpolationMethod(.linear)
                .foregroundStyle(KimaColor.textPrimary.opacity(0.14))
        }
        .chartXScale(domain: 0...23)
        .chartYScale(domain: 0...Double(max(1, maxPlays)))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                AxisValueLabel(anchor: labelAnchor(v.as(Int.self))) {
                    if let h = v.as(Int.self) {
                        Text(StatsFormat.hourLabel(h)).font(KimaType.caption).foregroundStyle(KimaColor.textFaint)
                    }
                }
            }
        }
        .frame(height: 52)
    }

    private func labelAnchor(_ hour: Int?) -> UnitPoint {
        switch hour {
        case 0: return .topLeading
        case 23: return .topTrailing
        default: return .top
        }
    }
}
