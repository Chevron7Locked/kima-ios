import XCTest
@testable import Kima

final class SSEFrameParserTests: XCTestCase {
    private func events(_ s: String) -> [SSEFrameParser.Event] {
        var p = SSEFrameParser()
        return s.utf8.compactMap { p.feed($0) }
    }

    func testSingleDataFrame() {
        let e = events("data: {\"type\":\"connected\"}\n\n")
        XCTAssertEqual(e, [.init(name: "message", data: "{\"type\":\"connected\"}")])
    }

    func testHeartbeatIgnored() {
        XCTAssertTrue(events(": heartbeat\n\n").isEmpty)
    }

    func testCRLF() {
        XCTAssertEqual(events("data: a\r\n\r\n"), [.init(name: "message", data: "a")])
    }

    func testMultiLineData() {
        XCTAssertEqual(events("data: a\ndata: b\n\n").first?.data, "a\nb")
    }

    func testNamedThenDefault() {
        XCTAssertEqual(events("event: ping\ndata: x\n\ndata: y\n\n").map(\.name), ["ping", "message"])
    }

    func testNoBlankLineNoEvent() {
        XCTAssertTrue(events("data: a\n").isEmpty)
    }
}
