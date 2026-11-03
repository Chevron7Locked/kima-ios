import XCTest
@testable import Kima

/// The line from the selected star to the readout's top edge.
final class VibeLeaderTests: XCTestCase {
    private let readout = CGRect(x: 16, y: 600, width: 282, height: 120)
    private let rail = CGRect(x: 310, y: 560, width: 64, height: 140)

    func testDropsStraightOntoTheReadoutsTopEdge() throws {
        let p = try XCTUnwrap(VibeLeader.points(star: CGPoint(x: 200, y: 300), ringRadius: 12.5,
                                                target: VibeLeaderTarget(readout: readout, rail: rail)))
        XCTAssertEqual(p, [CGPoint(x: 200, y: 316.5), CGPoint(x: 200, y: 596)],
                       "one straight line from just below the ring to just above the readout")
    }

    func testTurnsAboveTheRailInsteadOfCrossingIt() throws {
        let p = try XCTUnwrap(VibeLeader.points(star: CGPoint(x: 340, y: 300), ringRadius: 12.5,
                                                target: VibeLeaderTarget(readout: readout, rail: rail)))
        XCTAssertEqual(p[1].y, rail.minY - VibeLeader.clearance, "the drop stops above the rail")
        XCTAssertEqual(p.last?.x, readout.maxX, "it ends at the readout's corner")
        XCTAssertEqual(p.last?.y, readout.minY - VibeLeader.gap, "on its top edge")
        for (a, b) in zip(p, p.dropFirst()) {
            let segment = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                .insetBy(dx: -0.5, dy: -0.5)
            XCTAssertFalse(segment.intersects(rail), "segment \(a) → \(b) crosses the rail")
        }
    }

    func testNoLineWhenTheStarIsTooCloseToTheReadout() {
        XCTAssertNil(VibeLeader.points(star: CGPoint(x: 200, y: 570), ringRadius: 12.5,
                                       target: VibeLeaderTarget(readout: readout, rail: rail)))
    }
}
