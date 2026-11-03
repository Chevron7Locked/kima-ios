import XCTest
@testable import Kima

/// Map labels show only between the search list and the bottom stack.
final class VibeLabelBandTests: XCTestCase {
    func testLabelsShowOnlyFullyInsideTheOpenBand() {
        let band = VibeLabelBand(top: 200, bottom: 500)
        XCTAssertTrue(band.holds(y: 300))
        XCTAssertFalse(band.holds(y: 205), "half under the search list")
        XCTAssertFalse(band.holds(y: 495), "half behind the panel")
        XCTAssertFalse(band.holds(y: 600), "inside the panel")
        XCTAssertTrue(VibeLabelBand().holds(y: 600), "nothing open: labels show anywhere")
    }

    func testLabelsStayClearOfTheRail() {
        let band = VibeLabelBand(rail: CGRect(x: 330, y: 250, width: 60, height: 200))
        let size = CGSize(width: 60, height: 20)
        XCTAssertTrue(band.holds(centre: CGPoint(x: 200, y: 300), size: size), "well left of the rail")
        XCTAssertFalse(band.holds(centre: CGPoint(x: 300, y: 300), size: size), "right edge runs into the rail")
        XCTAssertFalse(band.holds(centre: CGPoint(x: 360, y: 350), size: size), "on top of the rail")
        XCTAssertTrue(band.holds(centre: CGPoint(x: 360, y: 150), size: size), "above the rail")
        XCTAssertTrue(VibeLabelBand().holds(centre: CGPoint(x: 360, y: 350), size: size), "no rail: no limit")
    }

    func testLabelsStayBelowTheMoodChips() {
        // Chips end at y 140: a label centred in the chip row, or touching it, is hidden.
        let band = VibeLabelBand(top: VibeLabelBand.top(hudBottom: 140, searchListBottom: nil), bottom: 700)
        XCTAssertFalse(band.holds(y: 120), "on the chips")
        XCTAssertFalse(band.holds(y: 145), "half over the chips")
        XCTAssertFalse(band.holds(y: 155), "touching the chips")
        XCTAssertTrue(band.holds(y: 160), "clear below the chips")
    }

    func testTheLowerOfChipsAndSearchListWins() {
        XCTAssertEqual(VibeLabelBand.top(hudBottom: 140, searchListBottom: 400), 400 + KimaSpacing.xl)
        XCTAssertEqual(VibeLabelBand.top(hudBottom: 140, searchListBottom: 100), 140 + KimaSpacing.sm)
        XCTAssertEqual(VibeLabelBand.top(hudBottom: nil, searchListBottom: nil), -.infinity)
    }
}
