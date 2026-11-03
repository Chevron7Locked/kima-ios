import XCTest
@testable import Kima

/// GET /whats-new/changelog and /update-status shapes, and the changelog's per-item state label.
final class ChangelogModelsTests: XCTestCase {
    private let json = #"""
    {"releases":[{"version":"1.12.0","title":"Moods","summary":"S","date":"2026-10-20","dismissed":true,
      "items":[
        {"key":"a","kind":"action","title":"Re-run","summary":"","body":"B","run":"wipeEnrichment","open":true,"done":false},
        {"key":"b","kind":"action","title":"Done","summary":"s","body":"B","done":true,"open":false},
        {"key":"c","kind":"choice","title":"Share","summary":"s","body":"B","answer":{"enabled":false,"decidedBy":"DISMISSED"}},
        {"key":"d","kind":"choice","title":"GPU","summary":"s","body":"B","answer":{"enabled":true,"decidedBy":"EXPLICIT"}},
        {"key":"e","kind":"note","title":"Note","summary":"s","body":"B"}]}],
     "openCount":1}
    """#

    func testChangelogDecodesStates() throws {
        let log = try JSONDecoder().decode(WhatsNewChangelog.self, from: Data(json.utf8))
        XCTAssertEqual(log.openCount, 1)
        let release = try XCTUnwrap(log.releases.first)
        let labels = release.items.map { ChangelogView.stateLabel($0)?.text }
        XCTAssertEqual(labels, ["open", "done", "off · unanswered", "you said on", nil])
        XCTAssertEqual(ChangelogView.stateLabel(release.items[0])?.isOpen, true)
    }

    func testPendingItemWithoutChangelogFieldsStillDecodes() throws {
        let item = try JSONDecoder().decode(WhatsNewItem.self, from: Data(
            #"{"key":"k","kind":"note","title":"T","summary":"S","body":"B"}"#.utf8))
        XCTAssertNil(item.answer)
        XCTAssertNil(ChangelogView.stateLabel(item))
    }

    func testUpdateStatus() throws {
        let status = try JSONDecoder().decode(ServerUpdateStatus.self, from: Data(
            #"{"enabled":true,"current":"1.12.0","latest":"1.13.0","hasUpdate":true,"lastCheckedAt":null}"#.utf8))
        XCTAssertTrue(status.hasUpdate)
        XCTAssertEqual(status.latest, "1.13.0")
        let off = try JSONDecoder().decode(ServerUpdateStatus.self, from: Data(
            #"{"enabled":false,"current":"1.12.0","latest":null,"hasUpdate":false,"lastCheckedAt":null}"#.utf8))
        XCTAssertNil(off.latest)
    }
}
