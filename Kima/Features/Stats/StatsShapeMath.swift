import Foundation
import CoreGraphics

/// Pure maths for the brightness and energy plot. Positions are percentages of
/// the plot side (0...100), y measured upward.
enum StatsShapeMath {
    struct Probe: Equatable { let x: Int; let y: Int }      // buckets 1...24
    static let buckets = 24
    static let pad = 4.2

    static func cellCentre(_ bucket: Int) -> Double {
        pad + ((Double(bucket) - 0.5) / Double(buckets)) * (100 - 2 * pad)
    }

    static func onScale(_ v: Double) -> Double { pad + v * (100 - 2 * pad) }

    static func bucketAt(_ pos: Double) -> Int {
        min(buckets, max(1, Int((((pos - pad) / (100 - 2 * pad)) * Double(buckets) + 0.5).rounded())))
    }

    static func dotRadius(plays: Int, max: Int) -> Double {
        0.7 + (Double(plays) / Double(max)).squareRoot() * 2.1
    }

    static func dotOpacity(plays: Int, max: Int) -> Double {
        0.2 + (Double(plays) / Double(max)).squareRoot() * 0.7
    }

    static func energyWord(_ e: Double) -> String {
        e < 0.4 ? "low energy" : (e > 0.6 ? "high energy" : "medium energy")
    }

    static func brightnessWord(_ v: Double) -> String {
        v < 0.4 ? "dark" : (v > 0.6 ? "bright" : "neutral")
    }

    static func overall(_ shape: [(x: Int, y: Int, plays: Int)]) -> (valence: Double, energy: Double)? {
        let n = shape.reduce(0) { $0 + $1.plays }
        guard n > 0 else { return nil }
        var v = 0.0, e = 0.0
        for s in shape {
            v += Double(s.plays) * ((Double(s.x) - 0.5) / Double(buckets))
            e += Double(s.plays) * ((Double(s.y) - 0.5) / Double(buckets))
        }
        return (v / Double(n), e / Double(n))
    }

    static func barest(_ shape: [(x: Int, y: Int, plays: Int)]) -> (name: String, percent: Int)? {
        let total = shape.reduce(0) { $0 + $1.plays }
        guard total > 0 else { return nil }
        // Order: dark/low, bright/low, dark/high, bright/high (mid = 12).
        var sums = [0, 0, 0, 0]
        for s in shape {
            sums[(s.y > 12 ? 2 : 0) + (s.x > 12 ? 1 : 0)] += s.plays
        }
        let names = ["dark, low energy", "bright, low energy", "dark, high energy", "bright, high energy"]
        var best = 0
        for i in 1..<4 where sums[i] < sums[best] { best = i }
        let share = Double(sums[best]) / Double(total)
        guard share < 0.05 else { return nil }
        return (names[best], Int((share * 100).rounded()))
    }

    static func movement(_ path: [(month: String, energy: Double, valence: Double)]) -> String? {
        guard path.count >= 3, let first = path.first, let last = path.last else { return nil }
        let dE = last.energy - first.energy
        let dV = last.valence - first.valence
        var parts: [String] = []
        if abs(dE) > 0.02 { parts.append(dE > 0 ? "higher energy" : "lower energy") }
        if abs(dV) > 0.02 { parts.append(dV > 0 ? "brighter" : "darker") }
        if parts.isEmpty { return "no change since \(monthLong(first.month))" }
        return "since \(monthLong(first.month)): \(parts.joined(separator: ", "))"
    }

    private static let longNames = ["january", "february", "march", "april", "may", "june", "july",
                                    "august", "september", "october", "november", "december"]

    private static func split(_ yyyyMM: String) -> (year: String, month: Int)? {
        let p = yyyyMM.split(separator: "-")
        guard p.count >= 2, let m = Int(p[1]), (1...12).contains(m) else { return nil }
        return (String(p[0]), m)
    }

    static func monthLong(_ yyyyMM: String) -> String {
        guard let s = split(yyyyMM) else { return yyyyMM }
        return "\(longNames[s.month - 1]) \(s.year)"
    }

    static func monthShort(_ yyyyMM: String) -> String {
        guard let s = split(yyyyMM) else { return yyyyMM }
        return "\(longNames[s.month - 1].prefix(3)) \(s.year.suffix(2))"
    }
}
