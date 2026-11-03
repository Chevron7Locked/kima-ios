import XCTest
@testable import Kima

final class NotificationListItemTests: XCTestCase {
    private func note(_ id: String, _ type: String, message: String? = nil) -> KimaNotification {
        KimaNotification(id: id, type: type, title: type, message: message, metadata: nil,
                         read: false, cleared: false, createdAt: "2026-10-08T12:00:00Z")
    }

    func testFailureMessageSplitsIntoAlbumAndReason() {
        let text = DownloadFailureText(message: "Failed to download The Algorithm - Data Renaissance: Import failed - no other release")
        XCTAssertEqual(text?.subject, "the algorithm - data renaissance")
        XCTAssertEqual(text?.reason, "import failed - no other release")
    }

    func testFailureMessageWithoutReasonKeepsTheAlbum() {
        let text = DownloadFailureText(message: "Failed to download Muse - Drones")
        XCTAssertEqual(text?.subject, "muse - drones")
        XCTAssertEqual(text?.reason, "")
    }

    func testOtherMessagesAreNotFailures() {
        XCTAssertNil(DownloadFailureText(message: "Your playlist is ready"))
        XCTAssertNil(DownloadFailureText(message: nil))
        XCTAssertNil(DownloadFailureText(message: "Failed to download "))
    }

    func testTwoOrMoreFailuresBecomeOneGroupWhereTheNewestWas() {
        let list = [note("a", "playlist_ready"), note("b", "download_failed"), note("c", "download_complete"),
                    note("d", "download_failed")]
        let items = NotificationListItem.items(from: list)
        XCTAssertEqual(items.map(\.id), ["a", "failures", "c"])
        if case .failures(let failed) = items[1] {
            XCTAssertEqual(failed.map(\.id), ["b", "d"])
        } else {
            XCTFail("expected the failure group second")
        }
    }

    func testOneFailureStaysOnItsOwn() {
        let items = NotificationListItem.items(from: [note("a", "download_failed"), note("b", "playlist_ready")])
        XCTAssertEqual(items.map(\.id), ["a", "b"])
    }
}
