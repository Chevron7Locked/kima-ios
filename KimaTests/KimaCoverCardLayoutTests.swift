import SwiftUI
import XCTest
@testable import Kima

/// Cover cards with a subtitle share one height whatever their title length; without one the name sizes itself.
@MainActor
final class KimaCoverCardLayoutTests: XCTestCase {
    private func height(_ title: String, _ subtitle: String?) -> CGFloat {
        let env = AppEnvironment(server: KimaServer(baseURL: URL(string: "https://kima.example.com")!))
        let card = KimaCoverCard(title: title, subtitle: subtitle, titleLines: 2, onTap: {}) {
            CoverArtImage(coverId: nil, size: 256, cornerRadius: 0)
        }
        .frame(width: 170)
        .environment(env)
        return UIHostingController(rootView: card).sizeThatFits(in: CGSize(width: 170, height: 2000)).height
    }

    func testAlbumCardHeightIgnoresTitleLength() {
        let oneLine = height("blue", "2019")
        XCTAssertEqual(height("a title long enough to wrap onto two lines", "2021"), oneLine)
        XCTAssertEqual(height("an album title so long that it would need three or four lines to show in full", "2004"), oneLine)
        XCTAssertEqual(height("blue", ""), oneLine, "an empty subtitle still keeps its line")
    }

    func testCardWithoutSubtitleSizesToItsName() {
        XCTAssertLessThan(height("blue", nil), height("an artist name long enough to wrap onto two lines", nil))
    }
}
