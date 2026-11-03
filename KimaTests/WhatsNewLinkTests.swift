import XCTest
@testable import Kima

final class WhatsNewLinkTests: XCTestCase {
    func testItemKeepsItsLinkTarget() throws {
        let json = #"{"kind":"action","key":"plays.repair","title":"t","body":"b","links":[{"label":"Open the cleanup","href":"/stats#false-starts"}]}"#
        let item = try JSONDecoder().decode(WhatsNewItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.links.first?.href, "/stats#false-starts")
        XCTAssertEqual(item.links.first?.label, "Open the cleanup")
    }

    func testItemWithoutLinksDecodes() throws {
        let item = try JSONDecoder().decode(WhatsNewItem.self, from: Data(#"{"kind":"note","key":"k","title":"t","body":"b"}"#.utf8))
        XCTAssertTrue(item.links.isEmpty)
    }
}
