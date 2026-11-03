import SwiftUI

// MARK: Also true (spoken word, sources, owned-against-played)

struct StatsAlsoTrue: View {
    let s: Signature
    let spoken: SpokenStats
    let l: ListeningStats
    let period: StatsPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            StatsFinding(claim: "other stats", scope: period == .all ? nil : "all time")
            VStack(alignment: .leading, spacing: KimaSpacing.xxl) {
                SpokenBlock(spoken: spoken)
                SourceBlock(listening: l)
                OwnedBlock(signature: s)
            }
        }
    }
}

private struct SpokenBlock: View {
    let spoken: SpokenStats

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            Text("podcasts & audiobooks").font(KimaType.caption).foregroundStyle(KimaColor.textSecondary)
            if spoken.audiobooks.seconds == 0 && spoken.podcasts.seconds == 0 {
                Text("no podcasts or audiobooks yet")
                    .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
            } else {
                if spoken.audiobooks.seconds > 0 {
                    Entry(value: StatsFormat.hours(spoken.audiobooks.seconds), unit: "hours of audiobooks", lines: {
                        let ab = spoken.audiobooks
                        let first = StatsShelfMath.joined([
                            ab.finished > 0 ? "\(ab.finished) finished" : nil,
                            ab.inProgress > 0 ? "\(ab.inProgress) in progress" : nil,
                            ab.setAside > 0 ? "\(ab.setAside) untouched 90+ days" : nil])
                        var lines: [String] = first.map { [$0] } ?? []
                        if let cur = ab.current {
                            lines.append("current: \(cur.title.lowercased()) · \(Int((cur.percent * 100).rounded()))%")
                        }
                        if let top = ab.topAuthors.first { lines.append("top author: \(top.name.lowercased())") }
                        return lines
                    }())
                }
                if spoken.podcasts.seconds > 0 {
                    Entry(value: StatsFormat.hours(spoken.podcasts.seconds), unit: "hours of podcasts", lines: {
                        let p = spoken.podcasts
                        let first = StatsShelfMath.joined([
                            p.subscriptions > 0 ? "\(p.subscriptions) \(p.subscriptions == 1 ? "subscription" : "subscriptions")" : nil,
                            p.finished > 0 ? "\(p.finished) \(p.finished == 1 ? "episode" : "episodes") finished" : nil])
                        var lines: [String] = first.map { [$0] } ?? []
                        if p.backlog > 0 {
                            lines.append("\(p.backlog.formatted(.number)) unplayed \(p.backlog == 1 ? "episode" : "episodes")")
                        }
                        return lines
                    }())
                }
            }
        }
    }
}

private struct Entry: View {
    let value: String
    let unit: String
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.sm) {
                Text(value).font(KimaType.figure).foregroundStyle(KimaColor.textPrimary).monospacedDigit()
                Text(unit).font(KimaType.caption).foregroundStyle(KimaColor.textSecondary)
            }
            ForEach(lines, id: \.self) { line in
                Text(line).font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
            }
        }
    }
}

private struct SourceBlock: View {
    let listening: ListeningStats

    // One hue, opacity carries the source; order puts
    // the Discover pair together so kept reads against offered.
    private static let order: [(key: String, say: String, alpha: Double)] = [
        ("LIBRARY", "library", 1.0),
        ("SUBSONIC", "subsonic apps", 0.62),
        ("DISCOVERY", "discover", 0.34),
        ("DISCOVERY_KEPT", "discover, kept", 0.80),
    ]

    var body: some View {
        let segments = Self.order
            .map { (s: $0, n: listening.bySource[$0.key] ?? 0) }
            .filter { $0.n > 0 }
        let dominantShare = segments.map { Double($0.n) / Double(max(1, listening.plays)) }.max() ?? 0
        if listening.plays > 0 && !segments.isEmpty {
            VStack(alignment: .leading, spacing: KimaSpacing.md) {
                Text("play sources").font(KimaType.caption).foregroundStyle(KimaColor.textSecondary)
                if dominantShare >= 0.97, let dominant = segments.max(by: { $0.n < $1.n }) {
                    Text("all plays from \(dominant.s.say)")
                        .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                } else {
                    GeometryReader { geo in
                        let widths = StatsShelfMath.segmentWidths(segments.map(\.n), total: listening.plays,
                                                                  width: Double(geo.size.width), gap: 2)
                        HStack(spacing: 2) {  // chart geometry: gap between bars/cells
                            ForEach(Array(segments.enumerated()), id: \.offset) { i, seg in
                                KimaColor.brand.opacity(seg.s.alpha)
                                    .frame(width: CGFloat(widths[i]), height: 8)
                            }
                        }
                    }
                    .frame(height: 8)
                    ForEach(segments, id: \.s.key) { seg in
                        HStack {
                            Text(seg.s.say).font(KimaType.body).foregroundStyle(KimaColor.textPrimary)
                            Spacer()
                            Text("\(Int((Double(seg.n) / Double(max(1, listening.plays)) * 100).rounded()))%")
                                .font(KimaType.caption).foregroundStyle(KimaColor.textSecondary).monospacedDigit()
                        }
                        .padding(.vertical, KimaSpacing.sm)
                        KimaHairline()
                    }
                    let offered = (listening.bySource["DISCOVERY"] ?? 0) + (listening.bySource["DISCOVERY_KEPT"] ?? 0)
                    let kept = listening.bySource["DISCOVERY_KEPT"] ?? 0
                    if offered > 0 {
                        Text("\(offered.formatted(.number)) discover plays · \(Int((Double(kept) / Double(offered) * 100).rounded()))% on albums you kept")
                            .font(KimaType.caption).foregroundStyle(KimaColor.textMuted).monospacedDigit()
                    }
                }
            }
        }
    }
}

private struct OwnedBlock: View {
    let signature: Signature

    var body: some View {
        // Grey tick = shelf, amber tick = what you play, on one track.
        if !signature.ownedVsPlayed.isEmpty {
            VStack(alignment: .leading, spacing: KimaSpacing.md) {
                Text("library vs played")
                    .font(KimaType.caption).foregroundStyle(KimaColor.textSecondary)
                Text("grey = library average · amber = played average")
                    .font(KimaType.caption).foregroundStyle(KimaColor.textFaint)
                ForEach(signature.ownedVsPlayed) { row in
                    let norm = { (v: Double) in max(0, min(1, row.unit == "bpm" ? v / 200 : v)) }
                    let fmt = { (v: Double) in row.unit == "bpm" ? String(Int(v.rounded())) : String(Int((v * 100).rounded())) }
                    VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                        HStack {
                            Text(StatsShelfMath.ownedLabel(row.label)).font(KimaType.caption).foregroundStyle(KimaColor.textSecondary)
                            Spacer()
                            Text("\(fmt(row.owned)) → \(fmt(row.played))")
                                .font(KimaType.caption).foregroundStyle(KimaColor.textMuted).monospacedDigit()
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(KimaColor.hairline.opacity(0.8)).frame(height: 3)
                                Rectangle().fill(KimaColor.textMuted)
                                    .frame(width: 3, height: 9)
                                    .offset(x: norm(row.owned) * geo.size.width - 1, y: -3)
                                Rectangle().fill(KimaColor.brand)
                                    .frame(width: 3, height: 11)
                                    .offset(x: norm(row.played) * geo.size.width - 1, y: -4)
                            }
                        }
                        .frame(height: 3)
                    }
                }
                if let e = signature.ownedVsPlayed.first(where: { $0.unit != "bpm" }) {
                    let harder = StatsShelfMath.harderPercent(owned: e.owned, played: e.played)
                    if harder > 3 {
                        Text("played energy: \(harder)% above library average")
                            .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                    }
                }
            }
        }
    }
}
