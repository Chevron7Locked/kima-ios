import XCTest

extension XCTestCase {
    /// Keeps a screenshot of the whole screen in the test report under `name`.
    func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Case-insensitive contains on a static text's label or value. Copy renders lowercased and
    /// SwiftUI Text exposes its string as the label, so exact-match queries are brittle.
    func text(_ app: XCUIApplication, contains needle: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", needle, needle)).firstMatch
    }
}
