import XCTest
@testable import Kima

/// The ServerTrust module answering synthetic challenges: what it accepts, what it blocks,
/// what it writes to pin storage, and what it reports to the observable state the UI binds.
/// Every answer arrives through exactly one completion — the invariant URLSession's own
/// challenge API demands of the adapter riding on this module.
final class ServerTrustHandlingTests: XCTestCase {
    private let host = "kima.lan"
    private let pin = "aa11"

    /// A presented self-signed certificate naming `host` with `publicKeyPin`, as the delegate
    /// adapter would describe a real challenge to the module.
    private func presented(
        _ publicKeyPin: String? = "aa11",
        systemValidated: Bool = false,
        namesHost: Bool = true
    ) -> ServerTrust.PresentedCertificate {
        .init(host: host, systemValidated: systemValidated, publicKeyPin: publicKeyPin, namesHost: namesHost)
    }

    /// The module over fake pin storage seeded by `configure`.
    private func makeTrust(
        configure: (FakeCertificatePins) -> Void = { _ in }
    ) -> (trust: ServerTrust, pins: FakeCertificatePins) {
        let pins = FakeCertificatePins()
        configure(pins)
        return (ServerTrust(pins: pins), pins)
    }

    /// Answer one challenge and collect every answer that arrives — "exactly once" is then an
    /// assertion at every site, not only where someone remembered to count.
    private func answersTo(
        _ trust: ServerTrust,
        _ certificate: ServerTrust.PresentedCertificate
    ) -> [ServerTrust.Answer] {
        var answers: [ServerTrust.Answer] = []
        trust.handle(certificate) { answers.append($0) }
        return answers
    }

    func testStoredPinAcceptsTheSameKeyNamingTheHost() {
        let (trust, _) = makeTrust { $0.results[host] = .found(pin) }

        XCTAssertEqual(answersTo(trust, presented()), [.useCredential], "a matching pin must be accepted exactly once")
    }

    @MainActor
    func testChangedKeyBlocksAndPrompts() async {
        let (trust, pins) = makeTrust { $0.results[host] = .found("bb22") }

        XCTAssertEqual(answersTo(trust, presented()), [.block], "a different key than the stored pin must be blocked exactly once")
        await waitUntil { trust.changes.shown != nil }
        XCTAssertEqual(trust.changes.shown, .init(host: host, keyChanged: true),
                       "the changed key must prompt with the option to trust the new certificate")
        XCTAssertTrue(pins.setCalls.isEmpty, "a change never re-pins; only the user's answer may")
    }

    @MainActor
    func testFirstUseCertificateNotNamingTheHostIsRefusedSilently() async {
        let (trust, pins) = makeTrust()   // nothing stored

        XCTAssertEqual(answersTo(trust, presented(namesHost: false)), [.block], "a certificate for another host must be blocked exactly once")
        XCTAssertTrue(pins.setCalls.isEmpty, "first use pins only a certificate that names this host")
        await Task.yield()
        XCTAssertNil(trust.changes.shown, "never-trusted isn't a change; nothing to prompt about")
    }

    @MainActor
    func testNameOnlyChangeBlocksAndPromptsWithoutATrustOption() async {
        let (trust, _) = makeTrust { $0.results[host] = .found(pin) }   // same key, but it no longer names the host

        XCTAssertEqual(answersTo(trust, presented(namesHost: false)), [.block])
        await waitUntil { trust.changes.shown != nil }
        XCTAssertEqual(trust.changes.shown, .init(host: host, keyChanged: false),
                       "trusting a key that doesn't name the host can't help, so the alert offers no trust button")
    }

    func testFirstUsePinsTheKeyThenAccepts() {
        let (trust, pins) = makeTrust()   // nothing stored

        XCTAssertEqual(answersTo(trust, presented()), [.useCredential])
        XCTAssertEqual(pins.setCalls.map(\.host), [host], "trust on first use stores this key")
        XCTAssertEqual(pins.results[host], .found(pin))
    }

    func testFailedPinWriteFailsClosed() {
        let (trust, _) = makeTrust { $0.writeSucceeds = false }

        XCTAssertEqual(answersTo(trust, presented()), [.block], "accepting without storing would silently re-pin on every connection")
    }

    @MainActor
    func testUnreadablePinStoreRefusesAndWritesNothing() async {
        let (trust, pins) = makeTrust { $0.results[host] = .failed(errSecInteractionNotAllowed) }

        XCTAssertEqual(answersTo(trust, presented()), [.block], "a failed read is not 'no pin': pinning would swap the stored key")
        XCTAssertTrue(pins.setCalls.isEmpty, "nothing may be written while storage is unreadable")
        await Task.yield()
        XCTAssertNil(trust.changes.shown, "unknown storage state is no evidence of a change; nothing to prompt")
    }

    func testSystemValidatedCertificatePassesThroughWithoutConsultingPins() {
        let (trust, pins) = makeTrust { $0.results[host] = .found("bb22") }   // a stored pin must not second-guess the CA chain

        XCTAssertEqual(answersTo(trust, presented(systemValidated: true)), [.defaultHandling])
        XCTAssertTrue(pins.readHosts.isEmpty, "publicly-trusted certificates never enter the TOFU layer")
    }

    func testCertificateWithoutExtractableKeyIsBlocked() {
        let (trust, pins) = makeTrust()

        XCTAssertEqual(answersTo(trust, presented(nil)), [.block], "no key to check means no basis to accept; fail safe")
        XCTAssertTrue(pins.readHosts.isEmpty)
    }

    // MARK: - The user's answer and the generation guard

    /// `testChangedKeyBlocksAndPrompts` is the control for this one: the same report does reach the
    /// state while the decision stands. Here the user answers before the in-flight report lands, so
    /// the older decision must lose — an alert for a change already trusted away must not appear.
    @MainActor
    func testStaleReportLosesToTheUsersNewerTrust() async {
        let (trust, _) = makeTrust { $0.results[host] = .found("bb22") }

        _ = answersTo(trust, presented())   // queues the report on the main actor; its answer already arrived
        trust.changes.trust(host: host)     // the user's newer decision, before it runs

        await Task.yield()   // let the queued report try to land
        XCTAssertNil(trust.changes.shown, "a challenge that read the old pin must not re-alert after the user trusted anew")
    }

    /// The recovery path at the interface: a blocked change prompts, the user trusts the new
    /// certificate, and the same server's next connection pins the key it presents.
    @MainActor
    func testTrustingTheNewCertificateLetsTheSameServerPinAnew() async {
        let (trust, pins) = makeTrust { $0.results[host] = .found("bb22") }

        XCTAssertEqual(answersTo(trust, presented()), [.block])
        await waitUntil { trust.changes.shown != nil }

        trust.changes.trust(host: host)
        XCTAssertEqual(pins.forgetCalls, [host], "trusting forgets the old pin so the next connection can store the new key")

        // the server reconnects with its new key
        XCTAssertEqual(answersTo(trust, presented()), [.useCredential], "after the user's answer the same certificate is first use again")
        XCTAssertEqual(pins.results[host], .found(pin))
    }
}
