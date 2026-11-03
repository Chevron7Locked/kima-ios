import XCTest

/// The vibe map's 202-computing poll, driven by `-kima-vibe-computing N` (the first N map fetches answer fake
/// {computing:true}). Proves the 202 contract in UI terms and the presentation hoist (the map is presented from
/// baseTabView, so its content is in the AX tree): a 202 shows "building the map", the 4s poll runs, a 200 removes it.
/// N=6 because the fake answers are counted from launch: the shell's own prefetch
/// (AppShellView+Observers, the accent-colour source) burns the first fetch, then the poll loop burns
/// one per 4s tick. Six fakes keep the map computing to ~24 s, so the copy is on screen at the row tap
/// and clears when the real answer lands.
final class VibePollUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        // `-kima-open stats` lands inside the More tab, so the home hero never renders and its opportunistic vibe prefetch
        // never fires. On a plain launch that prefetch burns the simulator's fake fetches behind the home screen.
        app.launchArguments = ["-kima-open", "stats", "-kima-vibe-computing", "6"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
    }

    @MainActor
    func testComputingAnswerShowsProgressThenPollsToReady() throws {
        let moreTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "more")).firstMatch
        XCTAssertTrue(moreTab.waitForExistence(timeout: 20), "shell never appeared")
        moreTab.tap()          // selects/pops the More tab to its root list
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "settings"))
                      .firstMatch.waitForExistence(timeout: 10), "more list never appeared")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "vibe map")).firstMatch
        for _ in 0..<10 where !row.isHittable {
            safeSwipeUp(app)
            _ = row.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(row.isHittable, "vibe map row never found in More")
        row.tap()

        // The cover is open: the app-root presentation puts its content in the
        // tree (runs 1/2: with the cover inside the tab / on a ZStack sibling,
        // the tree stayed the bare More list).
        let computing = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "building the map")).firstMatch
        XCTAssertTrue(computing.waitForExistence(timeout: 15),
                      "cover never surfaced computing copy — tree: \(app.debugDescription.prefix(4000))")
        attachScreenshot("vibe-computing")

        // Poll #1 (4s) is fake too; poll #2 (~8s) is the real server → ready.
        XCTAssertTrue(computing.waitForNonExistence(timeout: 60),
                      "poll loop never reached a ready answer: \(app.debugDescription.prefix(4000))")
        attachScreenshot("vibe-ready")
    }
}
