import XCTest
@testable import Kima

/// The iPad layout's sizing and routing rules: the full player's layouts, how far hero art reaches past the
/// readable column, and the sidebar's sections.
final class iPadLayoutTests: XCTestCase {

    // MARK: - Full player

    func testIPhoneKeepsTheSingleColumnAndTheSmallCover() {
        let layout = FullPlayerLayout(size: CGSize(width: 393, height: 800), isRegular: false)
        XCTAssertFalse(layout.sideBySide)
        XCTAssertEqual(layout.artworkSide, FullPlayerLayout.phoneArtworkSide)
    }

    func testCompactWidthOnIPadStaysTheIPhoneLayout() {
        // A narrow Split View window reports compact width even on a landscape iPad.
        let layout = FullPlayerLayout(size: CGSize(width: 507, height: 980), isRegular: false)
        XCTAssertFalse(layout.sideBySide)
        XCTAssertEqual(layout.artworkSide, FullPlayerLayout.phoneArtworkSide)
    }

    func testIPadPortraitStacksWithACoverSizedToTheScreen() {
        let layout = FullPlayerLayout(size: CGSize(width: 1032, height: 1336), isRegular: true)
        XCTAssertFalse(layout.sideBySide)
        XCTAssertEqual(layout.artworkSide, 1336 * 0.48, accuracy: 0.01)
        XCTAssertEqual(layout.controlsWidth, FullPlayerLayout.stackedControlsMax)
    }

    func testShortPortraitWindowShrinksTheCoverToFitTheControlsDownToItsMinimum() {
        let roomy = FullPlayerLayout(size: CGSize(width: 700, height: 1000), isRegular: true)
        XCTAssertEqual(roomy.artworkSide, 1000 - FullPlayerLayout.stackedControlsHeight, accuracy: 0.01)
        let short = FullPlayerLayout(size: CGSize(width: 700, height: 760), isRegular: true)
        XCTAssertFalse(short.sideBySide)
        XCTAssertEqual(short.artworkSide, FullPlayerLayout.stackedArtworkMin)
    }

    func testIPadLandscapePutsTheCoverBesideTheControlsAndFits() {
        for size in [CGSize(width: 1376, height: 988), CGSize(width: 1194, height: 790), CGSize(width: 1133, height: 700)] {
            let layout = FullPlayerLayout(size: size, isRegular: true)
            XCTAssertTrue(layout.sideBySide, "\(size)")
            XCTAssertLessThanOrEqual(layout.artworkSide, size.height - FullPlayerLayout.sideBySideChromeHeight, "\(size)")
            XCTAssertGreaterThan(layout.controlsWidth, 300, "\(size)")
            let used = layout.artworkSide + FullPlayerLayout.columnGap + layout.controlsWidth
            XCTAssertLessThanOrEqual(used, size.width - 2 * 48, "\(size): cover and controls fit with side margins")
        }
    }

    // MARK: - Hero bleed

    func testHeroArtReachesTheScreenEdgesOnlyWhenWiderThanTheColumn() {
        XCTAssertEqual(KimaLayout.columnBleed(viewport: 393), 0)
        XCTAssertEqual(KimaLayout.columnBleed(viewport: KimaLayout.readableWidth), 0)
        XCTAssertEqual(KimaLayout.columnBleed(viewport: 964), (964 - KimaLayout.readableWidth) / 2)
    }

    // MARK: - Sidebar

    func testSidebarReachesStatsAndPlaylists() {
        XCTAssertTrue(SidebarItem.indexed.contains(.stats))
        XCTAssertTrue(SidebarItem.indexed.contains(.playlists))
        XCTAssertFalse(SidebarItem.indexed.contains(.settings), "settings stays pinned in the footer")
    }

    #if DEBUG
    func testLaunchHooksLandOnTheirSidebarSection() {
        XCTAssertEqual(SidebarItem.debugLanding(for: "stats"), .stats)
        XCTAssertEqual(SidebarItem.debugLanding(for: "playlist"), .playlists)
        XCTAssertEqual(SidebarItem.debugLanding(for: "settings"), .settings)
        XCTAssertEqual(SidebarItem.debugLanding(for: "search"), .search)
        XCTAssertEqual(SidebarItem.debugLanding(for: "discover"), .discover)
        XCTAssertEqual(SidebarItem.debugLanding(for: "vibe"), .vibeMap)
        XCTAssertNil(SidebarItem.debugLanding(for: "album"), "detail pages open from their own section")
        XCTAssertNil(SidebarItem.debugLanding(for: nil))
    }
    #endif
}
