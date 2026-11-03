import Foundation
import CoreGraphics

/// Geometry and counting for the key wheel (circle of fifths), kept free of
/// SwiftUI so it can be compiled and checked on its own.
enum StatsKeyWheelMath {
    enum Ring: Equatable { case major, minor }
    /// `index` 0...11, 0 = top, clockwise.
    struct Wedge: Equatable { let index: Int; let ring: Ring }

    static let majors = ["C", "G", "D", "A", "E", "B", "F#", "Db", "Ab", "Eb", "Bb", "F"]
    static let minors = ["A", "E", "B", "F#", "C#", "G#", "Eb", "Bb", "F", "C", "G", "D"]
    static let enharmonic: [String: String] = ["Gb": "F#", "C#": "Db", "G#": "Ab", "D#": "Eb", "A#": "Bb",
                                               "Cb": "B", "Fb": "E", "E#": "F", "B#": "C"]
    // Fractions of R (R = half the wheel's side).
    static let majorInner = 0.67, majorOuter = 0.90
    static let minorInner = 0.38, minorOuter = 0.61
    static let majorLabelRadius = 0.785, minorLabelRadius = 0.495
    static let halfSpanDegrees = 13.8

    static func slot(_ pitch: String) -> String { enharmonic[pitch] ?? pitch }

    static func centreDegrees(_ index: Int) -> Double { Double(index) * 30 - 90 }

    static func counts(_ rows: [(key: String, scale: String, plays: Int)]) -> (major: [Int], minor: [Int]) {
        var major = [Int](repeating: 0, count: 12)
        var minor = [Int](repeating: 0, count: 12)
        for row in rows {
            let s = slot(row.key)
            if row.scale == "minor" {
                if let i = minors.firstIndex(where: { slot($0) == s }) { minor[i] += row.plays }
            } else if let i = majors.firstIndex(of: s) {
                major[i] += row.plays
            }
        }
        return (major, minor)
    }

    static func labelPoint(index: Int, ring: Ring, center: CGPoint, radius: CGFloat) -> CGPoint {
        let theta = centreDegrees(index) * .pi / 180
        let r = Double(radius) * (ring == .major ? majorLabelRadius : minorLabelRadius)
        return CGPoint(x: Double(center.x) + cos(theta) * r, y: Double(center.y) + sin(theta) * r)
    }

    static func hitTest(_ p: CGPoint, center: CGPoint, radius: CGFloat) -> Wedge? {
        let dx = Double(p.x - center.x), dy = Double(p.y - center.y)
        let r = hypot(dx, dy) / Double(radius)
        let ring: Ring
        if r >= 0.64 && r <= 1.0 { ring = .major }
        else if r >= 0.30 && r < 0.64 { ring = .minor }
        else { return nil }
        let deg = atan2(dy, dx) * 180 / .pi
        let rel = deg + 90 + 15
        let norm = (rel.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return Wedge(index: min(11, Int(norm / 30)), ring: ring)
    }

    static func share(_ plays: Int, max: Int) -> Double {
        plays == 0 ? 0 : pow(Double(plays) / Double(max), 0.6)
    }
    static func fillOpacity(_ plays: Int, max: Int) -> Double {
        plays == 0 ? 0 : 0.12 + 0.88 * share(plays, max: max)
    }
    static func isLoud(_ plays: Int, max: Int) -> Bool { Double(plays) / Double(max) > 0.45 }

    static func label(index: Int, ring: Ring) -> String {
        ring == .major ? majors[index].lowercased() : minors[index].lowercased() + "m"
    }
    static func displayName(index: Int, ring: Ring) -> String {
        ring == .major ? majors[index].lowercased() + " major" : minors[index].lowercased() + " minor"
    }
    /// Server spelling, not lowercased.
    static func apiKey(index: Int, ring: Ring) -> String {
        ring == .major ? majors[index] + " major" : minors[index] + " minor"
    }
}
