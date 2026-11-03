import CoreGraphics

/// Where the line from the selected star ends: the readout's top edge, kept clear of the tool rail.
/// Both frames are in screen points.
struct VibeLeaderTarget: Equatable {
    var readout: CGRect
    /// Nil until the rail has been measured.
    var rail: CGRect?
}

/// The corners of the line from the selected star to its readout: straight down from the star's ring
/// onto the readout's top edge. A star right of the readout (over the rail) goes down to just above
/// the readout, or above the rail when it would cross it, then across to the readout's corner. Pure.
enum VibeLeader {
    /// Space the line keeps from the rail.
    static let clearance: CGFloat = 12
    /// Gap between the line's end and the readout.
    static let gap: CGFloat = 4

    /// Nil when the star is too close to the readout, or below its top, for a line.
    static func points(star: CGPoint, ringRadius: CGFloat, target: VibeLeaderTarget) -> [CGPoint]? {
        let start = CGPoint(x: star.x, y: star.y + ringRadius + gap)
        let top = target.readout.minY - gap
        guard top - start.y > 16 else { return nil }
        let x = min(max(star.x, target.readout.minX), target.readout.maxX)
        if abs(x - star.x) < 1 { return [start, CGPoint(x: x, y: top)] }
        var knee = top
        if let rail = target.rail, start.x > rail.minX - clearance, start.x < rail.maxX + clearance,
           knee > rail.minY - clearance {
            knee = max(start.y, rail.minY - clearance)
        }
        var points = [start, CGPoint(x: star.x, y: knee), CGPoint(x: x, y: knee)]
        if knee < top { points.append(CGPoint(x: x, y: top)) }
        return points
    }
}
