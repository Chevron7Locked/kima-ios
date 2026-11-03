import XCTest

/// Shared scroll helper for suites that scroll their subject page. `app.swipeUp()` drags from ~85% height, the strip
/// where the mini-player's edge tab expands the full player, and restored playback puts player chrome there. A contained
/// drag from mid-screen (dy 0.62 -> 0.30) starts above that strip, scrolls, and doesn't dismiss sheets (press-then-drag).
/// Pass the app to scroll the screen or a ScrollView to scroll within its own bounds.
@MainActor
func safeSwipeUp(_ scroller: XCUIElement) {
    collapsePlayerOverlays(XCUIApplication())
    scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
       .press(forDuration: 0.05, thenDragTo: scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)))
}

extension XCUIElement {
    /// Scroll until the element lies entirely inside the window, and say whether it got there.
    ///
    /// `isHittable` is not enough evidence to tap. It returns true for an element whose CENTRE is
    /// below the fold — measured on the home made-for-you rail: a mix card at frame y 867.7,
    /// height 188.7 on a 440×956pt iPhone 17 Pro Max puts its centre at 962, six points off
    /// screen, and `card.tap()` then synthesises a touch at a point that does not exist, so the
    /// button never fires and the test waits out its timeout on a card it "could" tap.
    @MainActor
    func scrollToFullyVisible(in app: XCUIApplication, maxSwipes: Int = 10,
                              clearance: CGFloat = 12) -> Bool {
        func fits() -> Bool {
            let f = frame
            return f.height > 0 && f.minY >= 0 && f.maxY <= app.frame.maxY - clearance
        }
        for _ in 0...maxSwipes {
            if fits() { return true }
            guard exists else { return false }
            if frame.minY < 0 {
                // Above the top: drag down. Mid-screen start, so it stays clear of the chrome strips.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
                   .press(forDuration: 0.05,
                         thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)))
            } else {
                safeSwipeUp(app)
            }
            if !waitForExistence(timeout: 2) { return false }
        }
        return fits()
    }
}

/// Clears restored-playback chrome via the app's own user gestures — the only public
/// XCUITest surface (XCUIElement has no API for named accessibility actions, so the
/// card's "minimize player" action is driven the way a thumb drives it: drag right).
@MainActor
func collapsePlayerOverlays(_ app: XCUIApplication) {
    let header = app.staticTexts.matching(NSPredicate(format: "label == %@", "now playing")).firstMatch

    /// Tap the chevron (top-left, 44×44 at the leading edge of the top bar — FullPlayerView.swift
    /// topBar; the chevron has no stable identifier, so target its position: x ≈ 35pt of 440pt
    /// width, y ≈ 101pt of 956pt height).
    @MainActor func collapseFullPlayer() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.088, dy: 0.106))
           .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.088, dy: 0.106)))
        _ = header.waitForNonExistence(timeout: 3)
    }

    // Full player first, and retry until the header is really gone: it is a full-screen cover, so
    // while it is up the tab bar and every home target are unreachable. Five suites failing in the
    // full-suite run was this, not five bugs.
    for _ in 0..<3 where header.exists { collapseFullPlayer() }

    // Mini card: drag right past the 80pt threshold → minimize to the trailing edge tab
    // (MiniPlayerBar.swift:26 "drag right > 80 pt → minimize"). The drag starts left of
    // center on the card body — the play button owns the card's right edge, and a drag
    // that ends on the art/title (the tap gesture) would expand the full player instead.
    let card = app.buttons["expand-player"]
    if card.exists && !header.exists {
        // Drags are coordinate-to-coordinate (XCUIElement.press(...thenDragTo:) only takes
        // elements); start left-of-center on the card body — the play button owns the
        // right edge, and a drag ending on the art/title would tap-expand the full player.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.865)))
        _ = app.buttons.matching(NSPredicate(format: "label == %@", "restore player"))
                .firstMatch.waitForExistence(timeout: 2)
        // That drag became a tap, and the shell is covered again. Correct it here rather than
        // handing a covered screen back to the caller.
        if header.exists { for _ in 0..<2 { collapseFullPlayer() } }
    }
}
