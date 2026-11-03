import XCTest
@testable import Kima

/// The library masthead's line from the stats shelf, and how long a fetched copy is reused.
@MainActor
final class LibraryShelfSummaryTests: XCTestCase {

    override func tearDown() { StubURLProtocol.reset() }

    private static func statsJSON(total: Int, heard: Int) -> Data {
        let shelf = #"{"tracks":{"total":\#(total),"heard":\#(heard)},"albums":{"total":1,"heard":0},"artists":{"total":1,"heard":0},"analysis":{"done":0,"pending":0,"failed":0,"total":0},"neverPlayed":\#(total - heard),"decades":[]}"#
        return Data(#"{"period":"30d","listening":null,"shelf":\#(shelf),"spoken":null,"signature":null}"#.utf8)
    }

    private func gets() -> Int {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/stats") == true }.count
    }

    func testLineSaysHowMuchIsPlayed() async throws {
        StubURLProtocol.handler = { _ in (200, Self.statsJSON(total: 7615, heard: 533)) }
        let s = LibraryShelfSummary()
        await s.load(using: .stubbed())
        XCTAssertEqual(s.heardLine, "7% of library played · 7,082 tracks never played")
    }

    func testFreshCopyIsReusedAndForceFetches() async throws {
        StubURLProtocol.handler = { _ in (200, Self.statsJSON(total: 10, heard: 10)) }
        let s = LibraryShelfSummary()
        let t0 = Date()
        await s.load(using: .stubbed(), now: t0)
        await s.load(using: .stubbed(), now: t0.addingTimeInterval(60))
        XCTAssertEqual(gets(), 1)
        XCTAssertEqual(s.heardLine, "100% of library played")
        await s.load(using: .stubbed(), force: true, now: t0.addingTimeInterval(61))
        await s.load(using: .stubbed(), now: t0.addingTimeInterval(61 + LibraryShelfSummary.maxAge))
        XCTAssertEqual(gets(), 3)
    }

    func testFailureLeavesNoLine() async {
        StubURLProtocol.handler = { _ in (500, Data()) }
        let s = LibraryShelfSummary()
        await s.load(using: .stubbed())
        XCTAssertNil(s.heardLine)
    }
}
