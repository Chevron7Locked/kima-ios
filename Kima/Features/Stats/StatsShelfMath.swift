import Foundation

/// Pure maths and wording helpers for the unplayed / decades / other-stats blocks.
enum StatsShelfMath {
    /// Last two digits of the decade plus "s": 1970 -> "70s", 2000 -> "00s".
    static func decadeLabel(_ decade: Int) -> String {
        String(String(decade).suffix(2)) + "s"
    }

    /// Biggest decade by albums owned, and the least-played decade among those with 3+ albums.
    static func decadeSummary(_ d: [(decade: Int, albums: Int, heard: Int)]) -> (biggest: Int, coldest: Int?)? {
        guard !d.isEmpty, d.contains(where: { $0.albums > 0 }) else { return nil }
        var biggest = d[0]
        for row in d where row.albums > biggest.albums { biggest = row }
        var coldest: (decade: Int, albums: Int, heard: Int)?
        for row in d where row.albums >= 3 {
            if let c = coldest {
                if Double(row.heard) / Double(row.albums) < Double(c.heard) / Double(c.albums) { coldest = row }
            } else {
                coldest = row
            }
        }
        return (biggest.decade, coldest?.decade)
    }

    static func decadeSentence(biggest: Int, coldest: Int?) -> String {
        var s = "most albums: \(decadeLabel(biggest))"
        if let c = coldest, c != biggest { s += " · least played: \(decadeLabel(c))" }
        return s
    }

    /// Index of the centre closest to x; nil when there are no centres.
    static func nearestIndex(x: Double, centres: [Double]) -> Int? {
        guard !centres.isEmpty else { return nil }
        var best = 0
        for i in 1..<centres.count where abs(x - centres[i]) < abs(x - centres[best]) { best = i }
        return best
    }

    /// Bar segment widths that share `width` (minus the gaps), each at least 2 points.
    static func segmentWidths(_ counts: [Int], total: Int, width: Double, gap: Double) -> [Double] {
        let available = width - gap * Double(counts.count - 1)
        guard total > 0 else { return counts.map { _ in 2 } }
        return counts.map { max(2, Double($0) / Double(total) * available) }
    }

    /// How much higher the played average is than the owned average, in whole percent.
    static func harderPercent(owned: Double, played: Double) -> Int {
        Int((((played - owned) / max(0.01, owned)) * 100).rounded())
    }

    /// Joins the non-nil parts with " · "; nil when nothing is left.
    static func joined(_ parts: [String?]) -> String? {
        let kept = parts.compactMap { $0 }
        return kept.isEmpty ? nil : kept.joined(separator: " · ")
    }

    /// Maps the server's long measure names to the short ones shown in the app.
    static func ownedLabel(_ server: String) -> String {
        switch server {
        case "how hard it hits": return "energy"
        case "how bright it sounds": return "brightness"
        case "how instrumental": return "instrumental"
        case "beats a minute": return "bpm"
        default: return server.lowercased()
        }
    }
}
