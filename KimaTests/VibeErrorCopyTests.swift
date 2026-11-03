import XCTest
@testable import Kima

final class VibeErrorCopyTests: XCTestCase {

    private func http(_ status: Int, _ body: String? = nil) -> Error {
        APIError.http(status: status, body: body)
    }

    // Error bodies the server sends for blend and song path.
    private let alchemyNotReady = #"{"error":"Some tracks have not been through the similarity step yet"}"#
    private let pathNotReady = #"{"error":"One or both tracks have not been through the similarity step yet"}"#
    private let pathTooSimilar = #"{"error":"These tracks are too similar for a meaningful journey"}"#

    func testSimilar() {
        XCTAssertEqual(VibeErrorCopy.similar(http(404)), "not analysed yet")
        XCTAssertEqual(VibeErrorCopy.similar(http(500)), "couldn't load similar tracks")
        XCTAssertEqual(VibeErrorCopy.similar(URLError(.timedOut)), "couldn't load similar tracks")
    }

    func testAlchemy() {
        XCTAssertEqual(VibeErrorCopy.alchemy(http(400, alchemyNotReady)), "not analysed yet")
        XCTAssertEqual(VibeErrorCopy.alchemy(http(400, #"{"error":"Those tracks cancel each other out"}"#)),
                       "those tracks cancel out")
        XCTAssertEqual(VibeErrorCopy.alchemy(http(400, "bad")), "couldn't blend these tracks")
        XCTAssertEqual(VibeErrorCopy.alchemy(http(500)), "couldn't blend these tracks")
    }

    func testPath() {
        XCTAssertEqual(VibeErrorCopy.path(http(400, pathNotReady)), "not analysed yet")
        XCTAssertEqual(VibeErrorCopy.path(http(400, pathTooSimilar)), "too similar for a path")
        XCTAssertEqual(VibeErrorCopy.path(http(400, "other")), "couldn't find a path")
        XCTAssertEqual(VibeErrorCopy.path(http(500, pathTooSimilar)), "couldn't find a path")
    }

    func testMapLoad() {
        XCTAssertEqual(VibeErrorCopy.mapLoad(APIError.network(URLError(.notConnectedToInternet))),
                       "can't reach the server")
        XCTAssertEqual(VibeErrorCopy.mapLoad(http(500)), "map didn't load")
        XCTAssertEqual(VibeErrorCopy.mapLoad(APIError.decoding(URLError(.badServerResponse))),
                       "map didn't load")
        XCTAssertEqual(VibeErrorCopy.mapPollCap, "map still building — try again later")
    }
}
