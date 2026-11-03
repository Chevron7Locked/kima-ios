import XCTest
@testable import Kima

/// A drag in a reversed playlist must land where it looks: the server ranks `afterItemId` in stored order.
final class PlaylistReverseTests: XCTestCase {
    private func items(_ ids: [String]) throws -> [PlaylistItem] {
        let json = "[" + ids.map { #"{"id":"\#($0)","track":{"id":"t\#($0)","title":"t","duration":1}}"# }
            .joined(separator: ",") + "]"
        return try JSONDecoder().decode([PlaylistItem].self, from: Data(json.utf8))
    }

    /// Replays the server: each move puts the item right after its anchor in stored order (nil = front).
    private func apply(_ moves: [(itemId: String, afterItemId: String?)], to stored: [String]) -> [String] {
        var list = stored
        for move in moves {
            list.removeAll { $0 == move.itemId }
            let at = move.afterItemId.flatMap { a in list.firstIndex(of: a).map { $0 + 1 } } ?? 0
            list.insert(move.itemId, at: at)
        }
        return list
    }

    func testStoredOrderMovesUseShownAnchors() throws {
        // Stored a b c d, shown the same; drag d between a and b.
        let shown = try items(["a", "d", "b", "c"])
        let moves = PlaylistDetailViewModel.storedMoves(shown: shown, movedIDs: ["d"], reversed: false)
        XCTAssertEqual(moves.map(\.afterItemId), ["a"])
        XCTAssertEqual(apply(moves, to: ["a", "b", "c", "d"]), ["a", "d", "b", "c"])
    }

    func testReversedDragLandsWhereItLooks() throws {
        // Stored a b c d, shown d c b a; drag a to the top of the screen: shown a d c b.
        let shown = try items(["a", "d", "c", "b"])
        let moves = PlaylistDetailViewModel.storedMoves(shown: shown, movedIDs: ["a"], reversed: true)
        XCTAssertEqual(moves.map(\.afterItemId), ["d"])
        XCTAssertEqual(Array(apply(moves, to: ["a", "b", "c", "d"]).reversed()), ["a", "d", "c", "b"])
    }

    func testReversedMultiItemDrag() throws {
        // Stored a b c d e, shown e d c b a; move b and a between e and d: shown e b a d c.
        let shown = try items(["e", "b", "a", "d", "c"])
        let moves = PlaylistDetailViewModel.storedMoves(shown: shown, movedIDs: ["a", "b"], reversed: true)
        XCTAssertEqual(Array(apply(moves, to: ["a", "b", "c", "d", "e"]).reversed()), ["e", "b", "a", "d", "c"])
    }

    func testDetailDecodesReverseFlag() throws {
        let detail = try JSONDecoder().decode(PlaylistDetail.self, from: Data(
            #"{"id":"p","name":"n","reverseOrder":true,"items":[]}"#.utf8))
        XCTAssertEqual(detail.reverseOrder, true)
    }
}

/// Reversing a playlist reorders its cover mosaic too: covers used equally often keep the order they first appear in.
@MainActor
final class PlaylistReverseCoversTests: XCTestCase {
    override func tearDown() { StubURLProtocol.reset() }

    func testReversingReordersTheCovers() async throws {
        let items = ["1", "2", "3"].map {
            #"{"id":"i\#($0)","track":{"id":"t\#($0)","title":"t","duration":1,"album":{"coverArt":"c\#($0)"}}}"#
        }.joined(separator: ",")
        StubURLProtocol.handler = { req in
            req.httpMethod == "PATCH"
                ? (200, Data(#"{"id":"p","name":"n"}"#.utf8))
                : (200, Data(#"{"id":"p","name":"n","items":[\#(items)]}"#.utf8))
        }
        let vm = PlaylistDetailViewModel()
        await vm.load(id: "p", using: .stubbed())
        XCTAssertEqual(vm.coverIds, ["c1", "c2", "c3"])
        await vm.toggleReverse(playlistId: "p", using: .stubbed(), toast: ToastCenter())
        XCTAssertEqual(vm.coverIds, ["c3", "c2", "c1"])
    }
}
