import XCTest
@testable import Kima

/// Playlists repeat covers to fill the 2×2 mosaic; mixes show each distinct cover once.
final class MosaicCellsTests: XCTestCase {
    func testPlaylistsRepeatCoversDiagonally() {
        XCTAssertEqual(PlaylistMosaicView(coverIds: ["a", "b"]).filledCells(), ["a", "b", "b", "a"])
        XCTAssertEqual(PlaylistMosaicView(coverIds: ["a", "b", "c"]).filledCells(), ["a", "b", "c", "a"])
    }

    func testMixesShowEachCoverOnceUpToFour() {
        XCTAssertEqual(PlaylistMosaicView(coverIds: ["a", "a", "b"], fitsCovers: true).fittedCovers(), ["a", "b"])
        XCTAssertEqual(PlaylistMosaicView(coverIds: ["a", "", "b", "c"], fitsCovers: true).fittedCovers(), ["a", "b", "c"])
        XCTAssertEqual(PlaylistMosaicView(coverIds: ["a", "b", "c", "d", "e"], fitsCovers: true).fittedCovers(), ["a", "b", "c", "d"])
    }

    func testMosaicCoverIdsAreMostFrequentFirstWithoutRepeats() throws {
        let covers = ["b", "a", "b", "c", "b", "a"]
        let summary = try JSONDecoder().decode([PlaylistSummaryItem].self, from: Data(
            covers.enumerated().map { #"{"id":"\#($0.offset)","track":{"album":{"coverUrl":"\#($0.element)"}}}"# }
                .joined(separator: ",").wrapped(in: "[", "]").utf8))
        XCTAssertEqual(playlistMosaicCoverIds(from: summary), ["b", "a", "c"])
        let detail = try JSONDecoder().decode([PlaylistItem].self, from: Data(
            covers.enumerated().map { #"{"id":"\#($0.offset)","track":{"id":"t","title":"t","duration":1,"album":{"coverArt":"\#($0.element)"}}}"# }
                .joined(separator: ",").wrapped(in: "[", "]").utf8))
        XCTAssertEqual(playlistMosaicCoverIds(from: detail), ["b", "a", "c"])
        XCTAssertEqual(playlistMosaicCoverIds(from: nil as [PlaylistItem]?), [])
    }
}

private extension String {
    func wrapped(in open: String, _ close: String) -> String { open + self + close }
}
