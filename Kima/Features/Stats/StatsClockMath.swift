import Foundation
import CoreGraphics

/// Pure maths for the hour grid: ink strength, busiest cells, and tick positions.
enum StatsClockMath {
    struct Cell: Equatable, Hashable { let dow: Int; let hour: Int }

    /// Backend rows are Sunday-first; the grid reads Monday-first.
    static let rows = [1, 2, 3, 4, 5, 6, 0]

    /// The play count that gets full ink: the 85th percentile of lit cells,
    /// so one heavy hour does not wash out every quieter one.
    static func fullInk(_ clock: [[Int]]) -> Int {
        let lit = clock.flatMap { $0 }.filter { $0 > 0 }.sorted()
        if lit.isEmpty { return 1 }
        return max(1, lit[Int(floor(Double(lit.count) * 0.85))])
    }

    static func inkOpacity(_ n: Int, full: Int) -> Double {
        if n == 0 { return 0 }
        return 0.10 + 0.90 * min(1, pow(Double(n) / Double(full), 0.72))
    }

    static func busiest(_ clock: [[Int]], limit: Int = 3) -> [(cell: Cell, plays: Int)] {
        var all: [(cell: Cell, plays: Int)] = []
        for (dow, row) in clock.enumerated() {
            for (hour, n) in row.enumerated() where n > 0 {
                all.append((Cell(dow: dow, hour: hour), n))
            }
        }
        all.sort {
            if $0.plays != $1.plays { return $0.plays > $1.plays }
            if $0.cell.dow != $1.cell.dow { return $0.cell.dow < $1.cell.dow }
            return $0.cell.hour < $1.cell.hour
        }
        return Array(all.prefix(limit))
    }

    static func percentOfAll(_ n: Int, total: Int) -> String {
        if total <= 0 { return "0.0" }
        return String(format: "%.1f", Double(n) / Double(total) * 100)
    }

    /// Horizontal centre of an hour column in a row of 24 cells.
    static func columnCentre(hour: Int, width: CGFloat, spacing: CGFloat) -> CGFloat {
        let cell = (width - 23 * spacing) / 24
        return CGFloat(hour) * (cell + spacing) + cell / 2
    }
}
