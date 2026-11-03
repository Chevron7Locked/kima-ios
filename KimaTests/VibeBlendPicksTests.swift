import XCTest
@testable import Kima

final class VibeBlendPicksTests: XCTestCase {

    private func pick(_ id: String) -> VibeTrackPick { VibeTrackPick(id: id, title: id, artist: "a") }

    func testAddSkipsDuplicatesPerColumn() {
        var p = VibeBlendPicks()
        p.add(pick("1"), to: .more)
        p.add(pick("1"), to: .more)
        p.add(pick("1"), to: .less)
        XCTAssertEqual(p.more.map(\.id), ["1"])
        XCTAssertEqual(p.less.map(\.id), ["1"])
    }

    func testRemoveAndCanBlend() {
        var p = VibeBlendPicks()
        XCTAssertFalse(p.canBlend)
        p.add(pick("1"), to: .more)
        p.add(pick("2"), to: .more)
        XCTAssertTrue(p.canBlend)
        p.remove("1", from: .more)
        XCTAssertEqual(p.more.map(\.id), ["2"])
        p.remove("2", from: .more)
        XCTAssertFalse(p.canBlend)
    }

    @MainActor
    func testBlendResultsLightTheMapAndClearOnClose() {
        let vm = VibeMapViewModel()
        vm.panel = .blend
        var i = VibeHighlights.Input()
        i.blendIds = ["b1"]; i.similarIds = ["m1"]
        XCTAssertEqual(VibeHighlights.ids(i), ["b1"])
        i.searchIds = ["s"]
        XCTAssertEqual(VibeHighlights.ids(i), ["s"])
        vm.panel = nil
        XCTAssertTrue(vm.blendResults.isEmpty)
    }
}
