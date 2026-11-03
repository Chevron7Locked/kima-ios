import XCTest
@testable import Kima

@MainActor
final class VibeMapViewModelTests: XCTestCase {

    private func track(_ id: String, mood: String, colour: Double? = nil) -> VibeMapTrack {
        VibeMapTrack(id: id, x: 0.5, y: 0.5, title: id, artist: "a", artistId: "ar", albumId: "al",
                     coverUrl: nil, dominantMood: mood, moodScore: 0.5, moods: [:],
                     energy: nil, valence: nil, colour: colour)
    }

    private func response(_ tracks: [VibeMapTrack], signature: String? = "s1") -> VibeMapResponse {
        VibeMapResponse(tracks: tracks, trackCount: tracks.count,
                        computedAt: "2026-10-07T10:00:00Z", moodSignature: signature)
    }

    func testSameMapTwiceBuildsOnce() {
        let vm = VibeMapViewModel()
        let r = response([track("a", mood: "moodSad")])
        vm.apply(r)
        vm.apply(r)
        XCTAssertEqual(vm.mapGeneration, 1)
        vm.apply(response([track("a", mood: "moodSad")], signature: "s2"))
        XCTAssertEqual(vm.mapGeneration, 2)
        XCTAssertEqual(vm.mapKey, "2026-10-07T10:00:00Z|1|s2")
    }

    func testColourLookup() {
        let vm = VibeMapViewModel()
        vm.apply(response([track("a", mood: "moodSad", colour: 0.92), track("b", mood: "moodSad")]))
        XCTAssertEqual(vm.colour(for: "a"), 0.92)
        XCTAssertNil(vm.colour(for: "b"))
        XCTAssertNil(vm.colour(for: "zzz"))
        let plain = VibeMapViewModel()
        plain.apply(response([track("a", mood: "moodSad")], signature: nil))
        XCTAssertNil(plain.colour(for: "a"))
        XCTAssertEqual(plain.mapKey, "2026-10-07T10:00:00Z|1|-")
    }

    func testLegendOrderAndLabels() {
        var tracks: [VibeMapTrack] = []
        func add(_ n: Int, _ mood: String, _ tag: String) {
            tracks += (0..<n).map { track("\(tag)\($0)", mood: mood) }
        }
        add(20, "neutral", "n")      // first seen, but not a mood, so it sorts last
        add(100, "moodRelaxed", "r")
        add(100, "moodSad", "s")
        add(180, "moodAggressive", "g")
        let vm = VibeMapViewModel()
        vm.apply(response(tracks))
        XCTAssertEqual(vm.legendEntries.map(\.label),
                       ["intense", "calm", "melancholic", "no single mood"])
        XCTAssertEqual(vm.legendEntries.map(\.count), [180, 100, 100, 20])
        XCTAssertEqual(vm.tracksByMood["moodSad"]?.count, 100)
    }

    func testSoundAxesFoldIntoOneNoSingleMoodChip() {
        let tracks = [track("a1", mood: "acoustic"), track("a2", mood: "acoustic"),
                      track("e1", mood: "electronic"), track("n1", mood: "neutral"),
                      track("h1", mood: "happy")]
        let vm = VibeMapViewModel()
        vm.apply(response(tracks))
        XCTAssertEqual(vm.legendEntries.map(\.label), ["upbeat", "no single mood"])
        XCTAssertEqual(vm.legendEntries.map(\.count), [1, 4])
        XCTAssertEqual(Set(vm.tracksByMood["neutral"] ?? []), ["a1", "a2", "e1", "n1"])
    }

    func testUnanalysedAndUnknownLabels() {
        XCTAssertEqual(VibeMoodPalette.label(for: "unanalyzed"), "not analysed yet")
        XCTAssertEqual(VibeMoodPalette.label(for: "somethingElse"), "no single mood")
    }

    func testTogglePinAndClear() {
        let vm = VibeMapViewModel()
        vm.apply(response([track("a", mood: "moodSad"), track("n", mood: "neutral")]))
        vm.toggleLegend("moodSad")
        XCTAssertEqual(vm.legendPinned, "moodSad")
        XCTAssertEqual(vm.highlightedIds, ["a"], "a pinned chip lights its stars")
        vm.toggleLegend("neutral")
        XCTAssertEqual(vm.highlightedIds, ["n"], "the no-single-mood chip lights its stars too")
        vm.toggleLegend("neutral")
        XCTAssertNil(vm.legendPinned)
        XCTAssertEqual(vm.highlightedIds, [])
        vm.similarIds = ["a"]
        vm.toggleLegend("moodSad")   // clears the similar result first, then pins
        XCTAssertTrue(vm.similarIds.isEmpty)
        XCTAssertEqual(vm.legendPinned, "moodSad")
    }

    func testBackStepsBackOneThingPerTapNewestFirst() {
        let vm = VibeMapViewModel()
        vm.apply(response([track("a", mood: "moodSad"), track("b", mood: "moodSad")]))
        XCTAssertNil(vm.nextStepBack, "nothing to step back: back hides")
        vm.selectedTrackId = "a"
        vm.toggleLegend("moodSad")
        vm.similarIds = ["a", "b"]
        vm.searchQuery = "zz"
        vm.panel = .blend
        var steps: [VibeStepBack] = []
        while let step = vm.nextStepBack {
            steps.append(step)
            vm.stepBack()
        }
        // The pin's chip hides while a star is selected, so the selection goes before it.
        XCTAssertEqual(steps, [.closePanel, .clearSearch, .clearSimilar, .deselect, .unpinMood])
        XCTAssertNil(vm.panel)
        XCTAssertEqual(vm.searchQuery, "")
        XCTAssertTrue(vm.similarIds.isEmpty)
        XCTAssertNil(vm.legendPinned)
        XCTAssertNil(vm.selectedTrackId)
    }

    func testBackUndoesTheMostRecentThing() {
        let vm = VibeMapViewModel()
        vm.apply(response([track("a", mood: "moodSad"), track("b", mood: "moodSad")]))
        vm.searchQuery = "zz"
        vm.selectedTrackId = "a"
        XCTAssertEqual(vm.nextStepBack, .deselect, "the selection came after the search")
        vm.stepBack()
        XCTAssertEqual(vm.nextStepBack, .clearSearch)
        vm.panel = .songPath
        vm.searchQuery = "zzz"
        XCTAssertEqual(vm.nextStepBack, .clearSearch, "typing again makes the search the newest")
        vm.stepBack()
        XCTAssertEqual(vm.nextStepBack, .closePanel)
        vm.stepBack()
        XCTAssertNil(vm.nextStepBack)
    }

    func testBackSkipsWhatCannotBeSeen() {
        let vm = VibeMapViewModel()
        vm.apply(response([track("a", mood: "moodSad"), track("b", mood: "moodSad")]))
        vm.searchQuery = "b"
        vm.searchMatches = VibeLibrarySearch.Matches(query: "b", ids: ["b"], count: 1, top: [])
        vm.similarIds = ["a", "b"]
        XCTAssertEqual(vm.nextStepBack, .clearSearch, "the search's matches cover the newer similar result")
        vm.stepBack()
        XCTAssertEqual(vm.nextStepBack, .clearSimilar, "with the search gone the similar result shows")
    }

    func testBackLabelsAreVerbsAndVoiceOverHearsTheWholePhrase() {
        let vm = VibeMapViewModel()
        vm.apply(response([track("a", mood: "moodSad")]))
        XCTAssertEqual([VibeStepBack.closePanel, .clearSearch, .clearSimilar, .unpinMood, .deselect].map(\.railLabel),
                       ["close", "clear search", "clear similar", "unpin", "deselect"])
        vm.toggleLegend("moodSad")
        XCTAssertEqual(vm.stepBackSpokenLabel, "unpin melancholic")
        vm.selectedTrackId = "a"
        XCTAssertEqual(vm.stepBackSpokenLabel, "deselect a")
        vm.panel = .songPath
        XCTAssertEqual(vm.stepBackSpokenLabel, "close song path")
    }

    func testClearAllClosesPanelAndSearch() {
        let vm = VibeMapViewModel()
        vm.panel = .songPath
        vm.searchQuery = "abc"
        XCTAssertTrue(vm.hasActiveOverlay)
        vm.clearAll()
        XCTAssertNil(vm.panel)
        XCTAssertEqual(vm.searchQuery, "")
        XCTAssertFalse(vm.hasActiveOverlay)
    }
}
