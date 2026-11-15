import XCTest
@testable import Kima

/// Certificate changes for several hosts show one alert at a time, in the order they came in, and
/// the presentation lease between sheet-side and root-side alert copies lives here. The queueing
/// tests construct bare state with an inert answer; the wiring test pins what the answer is for.
@MainActor
final class ServerTrustStateTests: XCTestCase {
    /// Bare state with an inert answer; the queueing and lease tests never touch pin storage.
    private func makeState() -> ServerTrustState { ServerTrustState(onTrust: { _ in }) }

    /// "trust the new certificate" forwards the host to the answer the module installed —
    /// forgetting the old pin and bumping the generation is the module's, not the view's, business.
    func testTrustingForwardsToTheInstalledAnswer() {
        let answered = TrustAnswers()   // a box because the answer is typed @Sendable; used on main only
        let state = ServerTrustState(onTrust: { answered.hosts.append($0) })

        state.trust(host: "a.lan")

        XCTAssertEqual(answered.hosts, ["a.lan"])
    }

    func testSecondHostWaitsInsteadOfReplacingTheFirst() {
        let state = makeState()
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
        let state = makeState()
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
        let state = makeState()
        state.report(host: "a.lan", keyChanged: true)
        state.report(host: "b.lan", keyChanged: true)
        state.report(host: "a.lan", keyChanged: true)
        state.report(host: "b.lan", keyChanged: true)
        XCTAssertEqual(state.shown?.host, "a.lan")
        XCTAssertEqual(state.waiting.map(\.host), ["b.lan"])
    }

    func testAReportBetweenAlertsQueuesBehindTheWaitingOne() {
        let state = makeState()
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
        let state = makeState()
        state.report(host: "a.lan", keyChanged: true)
        state.report(host: "b.lan", keyChanged: true)
        state.showNext()
        XCTAssertEqual(state.shown?.host, "a.lan")
    }

    /// The lease the two alert copies bind: a sheet carrying its own copy takes presentation over
    /// the covered root-side copy — whose teardown would otherwise clear an unanswered change —
    /// and the covered side going quiet is never taken for answering.
    func testOverlayCopyTakesThePresentationLeaseFromTheRootSide() {
        let state = makeState()
        state.report(host: "a.lan", keyChanged: true)
        XCTAssertTrue(state.canPresent(overlay: false))
        XCTAssertTrue(state.canPresent(overlay: true))

        state.attachAlert(overlay: true)   // a sheet with its own copy opens over the root attachment
        XCTAssertFalse(state.canPresent(overlay: false), "the covered copy must not present")
        XCTAssertTrue(state.canPresent(overlay: true))

        state.detachAlert(overlay: true)   // the sheet closed unanswered
        XCTAssertTrue(state.canPresent(overlay: false), "the change falls back to the root-side copy")
        XCTAssertEqual(state.shown?.host, "a.lan", "going quiet is not answering")
    }

    func testNoChangePresentsOnEitherSide() {
        let state = makeState()
        XCTAssertFalse(state.canPresent(overlay: false))
        XCTAssertFalse(state.canPresent(overlay: true))
    }

    /// Only copies inside sheets move the lease; the root-side copy attaching changes nothing.
    func testRootSideAttachmentDoesNotMoveTheLease() {
        let state = makeState()
        state.report(host: "a.lan", keyChanged: true)
        state.attachAlert(overlay: false)
        XCTAssertTrue(state.canPresent(overlay: false))
        state.detachAlert(overlay: false)
        XCTAssertTrue(state.canPresent(overlay: false))
    }
}

/// A reference box so the wiring test can record hosts from a `@Sendable` answer; touched on main only.
private final class TrustAnswers: @unchecked Sendable {
    var hosts: [String] = []
}
