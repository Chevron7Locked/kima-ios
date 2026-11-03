import XCTest
@testable import Kima

final class VibeReadoutTests: XCTestCase {

    private func content(help: Bool = false, panel: Bool = false, selected: Bool = false) -> VibeReadout.Content {
        VibeReadout.content(helpOpen: help, panelOpen: panel, hasSelection: selected)
    }

    func testHelpCoversWhateverIsThere() {
        XCTAssertEqual(content(help: true), .help)
        XCTAssertEqual(content(help: true, selected: true), .help)
        XCTAssertEqual(content(help: true, panel: true, selected: true), .help)
    }

    func testPanelThenSelection() {
        XCTAssertEqual(content(panel: true, selected: true), .panel)
        XCTAssertEqual(content(selected: true), .track)
        XCTAssertEqual(content(), .none)
    }

    func testHelpListHasOneLinePerGestureAndTool() {
        XCTAssertEqual(VibeHelpView.gestures.map(\.key), ["tap a star", "double-tap", "drag", "pinch", "two fingers"])
        XCTAssertEqual(VibeHelpView.tools.map(\.key), ["song path", "blend"])
        XCTAssertEqual(VibeHelpView.actions.map(\.key), ["play", "play similar", "show similar", "more like", "less like"],
                       "one line per readout action")
        XCTAssertEqual(VibeHelpView.icons.map(\.key), ["back button", "labels button", "whole library button"],
                       "the back button and both unlabelled top-bar icons are named")
        XCTAssertEqual(VibeReadout.displayTitle("Blue Monday"), "blue monday")
    }
}
