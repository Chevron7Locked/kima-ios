import XCTest
@testable import Kima

/// Certificate changes for several hosts show one alert at a time, in the order they came in.
@MainActor
final class ServerTrustStateTests: XCTestCase {
    func testSecondHostWaitsInsteadOfReplacingTheFirst() {
        let state = ServerTrustState()
        state.report(host: "a.lan", keyChanged: true)
        state.report(host: "b.lan", keyChanged: false)

        XCTAssertEqual(state.shown, .init(host: "a.lan", keyChanged: true))
        XCTAssertEqual(state.waiting, [.init(host: "b.lan", keyChanged: false)])

        state.dismissShown()
        XCTAssertNil(state.shown, "the next alert waits for this one to close")
        state.showNext()
        XCTAssertEqual(state.shown, .init(host: "b.lan", keyChanged: false))
        XCTAssertTrue(state.waiting.isEmpty)

        state.dismissShown()
        state.showNext()
        XCTAssertNil(state.shown)
    }

    /// Closing an alert opens the next waiting one by itself, and a host reported while that is
    /// pending still gets its turn after.
    func testClosingAnAlertOpensTheNextOnItsOwn() async {
        let state = ServerTrustState()
        state.nextAlertDelay = .milliseconds(50)
        state.report(host: "a.lan", keyChanged: true)
        state.report(host: "b.lan", keyChanged: true)

        state.dismissShown()
        state.report(host: "c.lan", keyChanged: true)   // while b's opening is pending
        state.dismissShown()                             // a second close of the same alert changes nothing
        await state.advance?.value
        XCTAssertEqual(state.shown?.host, "b.lan")
        XCTAssertEqual(state.waiting.map(\.host), ["c.lan"])

        state.dismissShown()
        await state.advance?.value
        XCTAssertEqual(state.shown?.host, "c.lan")
        XCTAssertTrue(state.waiting.isEmpty)

        state.dismissShown()
        XCTAssertNil(state.advance, "nothing left to open")
        XCTAssertNil(state.shown)
    }

    func testRepeatReportsForOneHostRaiseOneAlert() {
        let state = ServerTrustState()
        state.report(host: "a.lan", keyChanged: true)
        state.report(host: "b.lan", keyChanged: true)
        state.report(host: "a.lan", keyChanged: true)
        state.report(host: "b.lan", keyChanged: true)
        XCTAssertEqual(state.shown?.host, "a.lan")
        XCTAssertEqual(state.waiting.map(\.host), ["b.lan"])
    }

    func testAReportBetweenAlertsQueuesBehindTheWaitingOne() {
        let state = ServerTrustState()
        state.report(host: "a.lan", keyChanged: true)
        state.report(host: "b.lan", keyChanged: true)
        state.dismissShown()
        state.report(host: "c.lan", keyChanged: true)   // while a closes and b has not shown yet
        XCTAssertNil(state.shown)
        state.showNext()
        XCTAssertEqual(state.shown?.host, "b.lan")
        XCTAssertEqual(state.waiting.map(\.host), ["c.lan"])
    }

    func testShowNextNeverReplacesAShownAlert() {
        let state = ServerTrustState()
        state.report(host: "a.lan", keyChanged: true)
        state.report(host: "b.lan", keyChanged: true)
        state.showNext()
        XCTAssertEqual(state.shown?.host, "a.lan")
    }
}
