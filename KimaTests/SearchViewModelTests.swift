import XCTest
@testable import Kima

@MainActor
final class SearchViewModelTests: XCTestCase {
    override func setUp() { StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset() }

    private let emptyLibrary = #"{"artists":[],"albums":[],"tracks":[],"podcasts":[],"audiobooks":[],"episodes":[]}"#

    func testSearchFailedWhenBothRequestsFail() async {
        StubURLProtocol.handler = { _ in (500, Data()) }
        let vm = SearchViewModel()
        await vm.performSearch(query: "ab", client: .stubbed())
        XCTAssertTrue(vm.searchFailed)
        XCTAssertFalse(vm.hasAnyResults)
    }

    func testSearchNotFailedWhenLibrarySucceeds() async {
        StubURLProtocol.handler = { [emptyLibrary] req in
            req.url?.path.hasSuffix("/search") == true ? (200, Data(emptyLibrary.utf8)) : (500, Data())
        }
        let vm = SearchViewModel()
        await vm.performSearch(query: "ab", client: .stubbed())
        XCTAssertFalse(vm.searchFailed)
        XCTAssertNotNil(vm.libraryResults)
    }
}
