import XCTest
@testable import Kima

/// The chart page's chips: a category's own sub-categories, or its siblings when it is one, after "all <parent>".
final class PodcastChartFamilyTests: XCTestCase {
    private let tree = [
        PodcastCategory(id: 1303, name: "Comedy", parentId: nil),
        PodcastCategory(id: 1495, name: "Improv", parentId: 1303),
        PodcastCategory(id: 1496, name: "Stand-Up", parentId: 1303),
        PodcastCategory(id: 1489, name: "News", parentId: nil),
    ]

    func testParentShowsItsChildren() {
        XCTAssertEqual(PodcastChartViewModel.family(of: tree[0], in: tree).map(\.name),
                       ["all Comedy", "Improv", "Stand-Up"])
    }

    func testChildShowsItsSiblings() {
        XCTAssertEqual(PodcastChartViewModel.family(of: tree[1], in: tree).map(\.id), [1303, 1495, 1496])
    }

    func testCategoryWithoutChildrenHasNoChips() {
        XCTAssertTrue(PodcastChartViewModel.family(of: tree[3], in: tree).isEmpty)
    }
}
