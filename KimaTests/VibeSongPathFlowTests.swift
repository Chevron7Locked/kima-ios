import XCTest
@testable import Kima

/// Song path as one flow: from a star the start is filled, the end comes from a tap or a search pick.
@MainActor
final class VibeSongPathFlowTests: XCTestCase {

    private func pick(_ id: String) -> VibeTrackPick { VibeTrackPick(id: id, title: id, artist: "a") }

    private func loadedModel() -> VibeMapViewModel {
        let tracks = ["s", "e", "x", "y"].map {
            VibeMapTrack(id: $0, x: 0, y: 0, title: "title \($0)", artist: "artist", artistId: "ar", albumId: "al",
                         coverUrl: nil, dominantMood: "moodSad", moodScore: 0.5, moods: [:],
                         energy: nil, valence: nil, colour: nil)
        }
        let vm = VibeMapViewModel()
        vm.apply(VibeMapResponse(tracks: tracks, trackCount: 4, computedAt: "t", moodSignature: "m"))
        return vm
    }

    func testFormFillsStartThenEndOnePromptAtATime() {
        var f = VibeSongPathForm()
        XCTAssertEqual(f.nextSlot, .start)
        XCTAssertFalse(f.canGenerate)
        f.fill(pick("a"))
        XCTAssertEqual(f.nextSlot, .end)
        f.fill(pick("a"))
        XCTAssertTrue(f.sameTrack)
        XCTAssertFalse(f.canGenerate)
        f.clear(.end)
        XCTAssertTrue(f.fill(pick("b")))
        XCTAssertNil(f.nextSlot)
        XCTAssertTrue(f.canGenerate)
        XCTAssertFalse(f.fill(pick("z")), "with both set, a pick changes nothing")
        XCTAssertEqual(f.end?.id, "b")
        f.clear(.start)
        XCTAssertEqual(f.nextSlot, .start)
        f.fill(pick("c"))
        XCTAssertEqual(f.start?.id, "c")
        XCTAssertEqual(f.end?.id, "b")
    }

    func testFromAStarTheStartIsFilledAndATapEndsIt() {
        let vm = loadedModel()
        vm.selectedTrackId = "s"
        vm.beginSongPath(from: "s")
        XCTAssertEqual(vm.panel, .songPath)
        XCTAssertEqual(vm.songPath.start, VibeTrackPick(id: "s", title: "title s", artist: "artist"))
        XCTAssertEqual(vm.selectedTrackId, "s", "starting a path keeps the selection")
        vm.handleTap(nil)
        XCTAssertNil(vm.songPath.end, "empty space keeps the flow open")
        XCTAssertEqual(vm.selectedTrackId, "s")
        vm.handleTap("e")
        XCTAssertEqual(vm.songPath.end?.id, "e")
        XCTAssertTrue(vm.songPath.canGenerate)
        XCTAssertEqual(vm.selectedTrackId, "s", "a tap that fills an end does not select")
    }

    func testWithBothEndsSetATapSelectsAndOnlySetAsMovesAnEnd() {
        let vm = loadedModel()
        vm.beginSongPath(from: "s")
        vm.handleTap("e")
        XCTAssertEqual(vm.pathStartMark, "s")
        XCTAssertEqual(vm.pathEndMark, "e")
        XCTAssertNil(vm.pathCandidate)
        vm.handleTap("x")
        XCTAssertEqual(vm.songPath.end?.id, "e", "a tap no longer overwrites the end")
        XCTAssertEqual(vm.selectedTrackId, "x", "it selects instead")
        XCTAssertEqual(vm.pathCandidate?.id, "x")
        vm.setSelected(as: .end)
        XCTAssertEqual(vm.songPath.end?.id, "x")
        XCTAssertNil(vm.pathCandidate, "the selected star is now the end")
        vm.handleTap("y")
        vm.setSelected(as: .start)
        XCTAssertEqual(vm.songPath.start?.id, "y", "set as start replaces the start")
        XCTAssertEqual(vm.songPath.end?.id, "x")
        vm.handleTap(nil)
        XCTAssertNil(vm.selectedTrackId, "empty space deselects once both ends are set")
        vm.songPath.clear(.end)
        vm.handleTap("e")
        XCTAssertEqual(vm.songPath.end?.id, "e", "after its × the next tap fills the end again")
        vm.panel = nil
        XCTAssertNil(vm.pathStartMark, "the marks show only while the song path is open")
        XCTAssertNil(vm.pathEndMark)
    }

    func testClosingTheSongPathKeepsItsEnds() {
        let vm = loadedModel()
        vm.beginSongPath(from: "s")
        vm.handleTap("e")
        vm.panel = nil
        XCTAssertEqual(vm.songPath.start?.id, "s")
        XCTAssertEqual(vm.songPath.end?.id, "e", "reopening shows the same two ends")
        vm.handleTap("x")
        XCTAssertEqual(vm.selectedTrackId, "x", "with the panel closed a tap selects again")
        vm.beginSongPath(from: "x")
        XCTAssertEqual(vm.songPath.start?.id, "x")
        XCTAssertEqual(vm.songPath.end?.id, "e", "a new start keeps the end")
        vm.beginSongPath(from: "e")
        XCTAssertNil(vm.songPath.end, "the end goes when it becomes the start")
    }

    func testReadoutMoreAndLessLikeOpenBlendAndAddTheStar() {
        let vm = loadedModel()
        vm.addToBlend("s", column: .more)
        XCTAssertEqual(vm.panel, .blend)
        vm.addToBlend("e", column: .less)
        vm.addToBlend("s", column: .more)
        XCTAssertEqual(vm.blendPicks.more.map(\.id), ["s"])
        XCTAssertEqual(vm.blendPicks.less.map(\.id), ["e"])
        XCTAssertEqual(vm.blendPicks.more.first?.title, "title s")
        vm.panel = nil
        XCTAssertEqual(vm.blendPicks.more.map(\.id), ["s"], "closing blend keeps its picks")
        vm.panel = .blend
        XCTAssertEqual(vm.blendPicks.less.map(\.id), ["e"], "reopening shows them")
    }

    func testBlendFromTheReadoutSwitchesFromSongPathAndKeepsItsEnds() {
        let vm = loadedModel()
        vm.beginSongPath(from: "s")
        vm.addToBlend("e", column: .more)
        XCTAssertEqual(vm.panel, .blend)
        XCTAssertEqual(vm.songPath.start?.id, "s")
        XCTAssertEqual(vm.blendPicks.more.map(\.id), ["e"])
    }

    func testRailToolsStartFromTheSelectedStar() {
        let vm = loadedModel()
        vm.selectedTrackId = "s"
        vm.toggleTool(.songPath)
        XCTAssertEqual(vm.panel, .songPath)
        XCTAssertEqual(vm.songPath.start?.id, "s", "the selected star is the start")
        XCTAssertEqual(vm.songPath.nextSlot, .end)
        vm.toggleTool(.songPath)
        XCTAssertNil(vm.panel, "tapping the open tool closes it")

        vm.selectedTrackId = "e"
        vm.toggleTool(.blend)
        XCTAssertEqual(vm.panel, .blend)
        XCTAssertEqual(vm.blendPicks.more.map(\.id), ["e"], "the selected star joins more like")
        XCTAssertEqual(vm.selectedTrackId, "e", "blend keeps the selection for when it closes")
    }

    func testRailToolsWithNothingSelectedOpenEmpty() {
        let vm = loadedModel()
        vm.toggleTool(.songPath)
        XCTAssertEqual(vm.panel, .songPath)
        XCTAssertEqual(vm.songPath, VibeSongPathForm())
        vm.toggleTool(.blend)
        XCTAssertEqual(vm.panel, .blend, "the other tool switches panels")
        XCTAssertEqual(vm.blendPicks, VibeBlendPicks())
    }

    func testSwapTradesTheEndsAndMovesAnEmptyOne() {
        var form = VibeSongPathForm()
        form.fill(VibeTrackPick(id: "s", title: "s", artist: "a"))
        form.swap()
        XCTAssertNil(form.start)
        XCTAssertEqual(form.end?.id, "s")
        XCTAssertEqual(form.nextSlot, .start, "the empty start is asked for next")
        form.fill(VibeTrackPick(id: "t", title: "t", artist: "a"))
        form.swap()
        XCTAssertEqual(form.start?.id, "s")
        XCTAssertEqual(form.end?.id, "t")
    }
}

/// How a pick row splits its line between the title and the artist.
final class VibeTitleArtistLayoutTests: XCTestCase {
    private func widths(_ t: CGFloat, _ a: CGFloat, in w: CGFloat) -> (title: CGFloat, artist: CGFloat) {
        VibeTitleArtistLayout.widths(title: t, artist: a, available: w, spacing: 8)
    }

    func testBothFitWhole() {
        let w = widths(60, 40, in: 200)
        XCTAssertEqual(w.title, 60); XCTAssertEqual(w.artist, 40)
    }

    func testTheTitleGivesWayAndTheArtistStays() {
        let w = widths(125, 52, in: 158)
        XCTAssertEqual(w.artist, 52, "the artist keeps its width")
        XCTAssertEqual(w.title, 98, "the title takes what is left")
    }

    func testPastHalfTheLineBothShorten() {
        let w = widths(125, 110, in: 158)
        XCTAssertEqual(w.title, 75, "the title keeps half")
        XCTAssertEqual(w.artist, 75)
    }

    func testAShortTitleLeavesTheRestToTheArtist() {
        let w = widths(40, 200, in: 158)
        XCTAssertEqual(w.title, 40)
        XCTAssertEqual(w.artist, 110)
    }
}
