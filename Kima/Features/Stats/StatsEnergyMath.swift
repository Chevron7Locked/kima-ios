import Foundation

/// Maths for the energy-by-hour chart. Ported from the web EnergyCurve.
enum StatsEnergyMath {
    struct Hour: Equatable, Identifiable {
        let hour: Int
        let plays: Int
        let energy: Double
        let raw: Double?
        var id: Int { hour }
    }

    /// 24 rows. Hours with no plays carry the previous reading (the first
    /// played reading before any play), so the curve never drops to zero.
    static func rows(_ hourly: [(hour: Int, plays: Int, energy: Double)]) -> [Hour] {
        var byHour: [Int: (hour: Int, plays: Int, energy: Double)] = [:]
        for h in hourly where byHour[h.hour] == nil { byHour[h.hour] = h }
        let firstPlayed = byHour.values.filter { $0.plays > 0 }.min(by: { $0.hour < $1.hour })
        var last = firstPlayed?.energy ?? 0.5
        return (0..<24).map { h in
            let entry = byHour[h]
            var raw: Double? = nil
            if let entry, entry.plays > 0 { last = entry.energy; raw = entry.energy }
            return Hour(hour: h, plays: entry?.plays ?? 0, energy: last, raw: raw)
        }
    }

    static func playedCount(_ rows: [Hour]) -> Int { rows.filter { $0.plays > 0 }.count }

    /// 24 values in 0...1. The span is floored so a steady day is not stretched.
    static func normalized(_ rows: [Hour]) -> [Double] {
        let raws = rows.filter { $0.plays > 0 }.compactMap { $0.raw }
        guard let lo = raws.min(), let hi = raws.max() else { return rows.map { _ in 0.5 } }
        let range = hi - lo
        let span = max(0.08, range)
        let base = lo - (span - range) / 2
        return rows.map { ($0.energy - base) / span }
    }

    static func frantic(_ rows: [Hour]) -> Int? {
        var best: Hour?
        for r in rows where r.plays > 0 {
            if best == nil || (r.raw ?? 0) > (best?.raw ?? 0) { best = r }
        }
        return best?.hour
    }

    static func calmest(_ rows: [Hour]) -> Int? {
        var best: Hour?
        for r in rows where r.plays > 0 {
            if best == nil || (r.raw ?? 0) < (best?.raw ?? 0) { best = r }
        }
        return best?.hour
    }
}
