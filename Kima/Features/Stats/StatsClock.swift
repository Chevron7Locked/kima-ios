import SwiftUI

// MARK: Rhythm (listening clock: 7×24, Monday first, cell tap drills)

struct StatsRhythm: View {
    let l: ListeningStats
    let onCell: (_ weekday: Int, _ hour: Int) -> Void

    @State private var selected: StatsClockMath.Cell?

    private static let rowLabels = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    private typealias Math = StatsClockMath

    private func plays(_ c: Math.Cell) -> Int {
        c.dow < l.clock.count && c.hour < l.clock[c.dow].count ? l.clock[c.dow][c.hour] : 0
    }

    private func when(_ c: Math.Cell) -> String {
        StatsFormat.whenLabel(weekday: c.dow, hour: c.hour)
    }

    private func playsText(_ n: Int) -> String {
        n == 1 ? "1 play" : "\(n.formatted(.number)) plays"
    }

    var body: some View {
        let full = Math.fullInk(l.clock)
        let peak = l.peak.map { Math.Cell(dow: $0.weekday, hour: $0.hour) }
        let shown = selected ?? peak
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            if let peak {
                StatsFinding(
                    claim: "busiest hour: \(when(peak))",
                    note: "plays by day and hour · local time")
            }
            grid(full: full)
            ticks
            if let shown { caption(shown, peak: peak) }
            busiestRows
        }
        .onChange(of: l.plays) { selected = nil }
    }

    private func grid(full: Int) -> some View {
        let shownDow = (selected ?? l.peak.map { Math.Cell(dow: $0.weekday, hour: $0.hour) })?.dow
        return VStack(spacing: 3) {  // chart geometry: gap between bars/cells
            ForEach(Array(Math.rows.enumerated()), id: \.offset) { rowIdx, dow in
                HStack(spacing: KimaSpacing.xs) {
                    Text(Self.rowLabels[rowIdx])
                        .font(KimaType.caption)
                        .foregroundStyle(shownDow == dow ? KimaColor.textPrimary : KimaColor.textFaint)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 30, alignment: .leading)
                    HStack(spacing: 2) {  // chart geometry: gap between bars/cells
                        ForEach(0..<24, id: \.self) { hour in
                            cell(Math.Cell(dow: dow, hour: hour), full: full)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ c: Math.Cell, full: Int) -> some View {
        let n = plays(c)
        return RoundedRectangle(cornerRadius: 2)
            .fill(n == 0 ? Color.white.opacity(0.05) : KimaColor.brand.opacity(Math.inkOpacity(n, full: full)))
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .overlay {
                if selected == c { RoundedRectangle(cornerRadius: 2).stroke(Color.white, lineWidth: 1.5) }
            }
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(n > 0 ? "\(when(c)): \(playsText(n))" : "\(when(c)): no plays")
            .accessibilityIdentifier("clock-\(c.dow)-\(c.hour)")
            .accessibilityAddTraits(n > 0 ? .isButton : [])
            .onTapGesture {
                selected = c
                if n > 0 { onCell(c.dow, c.hour) }
            }
    }

    private var ticks: some View {
        HStack(spacing: KimaSpacing.xs) {
            Color.clear.frame(width: 30, height: 16)
            GeometryReader { geo in
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    Text(StatsFormat.hourLabel(h))
                        .font(KimaType.caption).foregroundStyle(KimaColor.textFaint)
                        .fixedSize()
                        .position(x: Math.columnCentre(hour: h, width: geo.size.width, spacing: 2), y: 8)  // the hour label over its column (columns 2pt apart)
                }
            }
            .frame(height: 16)
        }
    }

    private func caption(_ shown: Math.Cell, peak: Math.Cell?) -> some View {
        let n = plays(shown)
        var detail = n == 0
            ? "no plays"
            : "\(playsText(n)) · \(Math.percentOfAll(n, total: l.plays))% of all plays"
        if n > 0, shown == peak { detail += " · busiest" }
        return VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            Text(when(shown)).font(KimaType.headline).foregroundStyle(KimaColor.textPrimary)
            Text(detail).font(KimaType.caption).foregroundStyle(KimaColor.textMuted).monospacedDigit()
        }
        .frame(minHeight: 40, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clock-caption")
    }

    @ViewBuilder private var busiestRows: some View {
        let top = Math.busiest(l.clock)
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("busiest hours").font(KimaType.caption).foregroundStyle(KimaColor.textSecondary)
                ForEach(top, id: \.cell) { entry in
                    Button {
                        selected = entry.cell
                        onCell(entry.cell.dow, entry.cell.hour)
                    } label: {
                        HStack {
                            Text(when(entry.cell)).font(KimaType.body).foregroundStyle(KimaColor.textPrimary)
                            Spacer()
                            Text(playsText(entry.plays)).font(KimaType.caption)
                                .foregroundStyle(KimaColor.textMuted).monospacedDigit()
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("busiest-hour-\(entry.cell.dow)-\(entry.cell.hour)")
                    KimaHairline()
                }
            }
        }
    }
}
