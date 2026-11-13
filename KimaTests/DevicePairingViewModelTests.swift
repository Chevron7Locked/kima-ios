import XCTest
@testable import Kima

@MainActor
final class DevicePairingViewModelTests: KeychainLoginTestCase {
    private let server = KimaServer(baseURL: URL(string: "https://link.example:8443")!)
    private var linked = 0

    override func setUpWithError() throws {
        try super.setUpWithError()   // snapshot, clean slate, hard writability assert (ticket 10 ruling)
        linked = 0
    }

    private var link: DevicePairingLink { DevicePairingLink(code: "ABC234", server: server) }

    private func makeVM(_ request: DevicePairingRequest? = nil,
                        phase: SessionStore.Phase = .unauthenticated) -> DevicePairingViewModel {
        var linker = DeviceLinker()
        linker.makeClient = { at, _ in KimaAPIClient(server: at, sessions: StubSessionFactory()) }
        linker.deviceName = { "test phone" }
        return DevicePairingViewModel(request: request ?? .link(link), linker: linker,
                                      currentPhase: { phase }, onLinked: { [unowned self] in linked += 1 })
    }

    private func respond(_ status: Int, _ body: String = "{}") {
        StubURLProtocol.handler = { _ in (status, Data(body.utf8)) }
    }

    func testOpeningALinkSendsNothingUntilConfirm() async {
        let vm = makeVM()
        XCTAssertEqual(vm.step, .confirm(link))
        await Task.yield()
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testConfirmSendsTheCodeToTheLinksServer() async {
        respond(200, #"{"success":true,"apiKey":"key-1","userId":"u","username":"n"}"#)
        let vm = makeVM()
        vm.confirm()
        await vm.linkTask?.value
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        let req = StubURLProtocol.requests[0]
        XCTAssertEqual(req.url?.absoluteString, "https://link.example:8443/api/device-link/verify")
        XCTAssertEqual(StubURLProtocol.posts(to: "/device-link/verify").first?["code"] as? String, "ABC234")
        XCTAssertEqual(StubURLProtocol.posts(to: "/device-link/verify").first?["deviceName"] as? String, "test phone")
        XCTAssertEqual(KeychainStore.credential(KeychainStore.apiKey, for: server), "key-1")
        XCTAssertEqual(ServerURLStore.stored, "https://link.example:8443")
        XCTAssertEqual(linked, 1)
    }

    func testStatusesMapToMessages() async {
        let cases: [(Int, String, Bool)] = [
            (403, "the link was denied.", false),
            (408, "nobody approved it in time. try again.", true),
            (409, "another device is already waiting on this code.", true),
            (404, "that code didn't work. get a new one and try again.", false),
            (400, "that code didn't work. get a new one and try again.", false),
            (429, "too many tries. wait a few minutes and try again.", false),
            (500, "the server returned an error (500).", false),
        ]
        for (status, message, canRetry) in cases {
            respond(status, #"{"error":"raw server text"}"#)
            let vm = makeVM()
            vm.confirm()
            await vm.linkTask?.value
            XCTAssertEqual(vm.step, .failed(message: message, retry: canRetry ? link : nil), "\(status)")
        }
        XCTAssertNil(KeychainStore.credential(KeychainStore.apiKey, for: server))
        XCTAssertNil(ServerURLStore.stored)
        XCTAssertEqual(linked, 0)
    }

    func testDroppedConnectionOffersRetryWithoutRawText() {
        let result = DeviceLinker.failure(for: APIError.network(URLError(.networkConnectionLost)))
        XCTAssertEqual(result, .failed(message: "couldn't reach the server. check the address and your connection.",
                                       canRetry: true))
    }

    func testSuccessEndsInTheLinkedStep() async {
        respond(200, #"{"success":true,"apiKey":"key-4"}"#)
        let vm = makeVM()
        vm.confirm()
        await vm.linkTask?.value
        XCTAssertEqual(vm.step, .linked)
        XCTAssertEqual(linked, 1)
    }

    func testTimeoutRetrySendsTheSameCode() async {
        respond(408)
        let vm = makeVM()
        vm.confirm()
        await vm.linkTask?.value
        respond(200, #"{"success":true,"apiKey":"key-2"}"#)
        vm.retry()
        await vm.linkTask?.value
        let codes = StubURLProtocol.posts(to: "/device-link/verify").compactMap { $0["code"] as? String }
        XCTAssertEqual(codes, ["ABC234", "ABC234"])
        XCTAssertEqual(linked, 1)
    }

    func testCancelWritesNothingAndShowsNoError() async {
        respond(200, #"{"success":true,"apiKey":"key-3"}"#)
        let vm = makeVM()
        vm.confirm()
        vm.cancel()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(KeychainStore.credential(KeychainStore.apiKey, for: server))
        XCTAssertNil(ServerURLStore.stored)
        XCTAssertEqual(linked, 0)
        XCTAssertEqual(vm.step, .confirm(link))
    }

    func testSignedInOrLaunchingNeverSends() async {
        for phase in [SessionStore.Phase.authenticated(host: "h"), .launching] {
            let vm = makeVM(phase: phase)
            vm.confirm()
            await vm.linkTask?.value
            XCTAssertEqual(vm.step, .confirm(link))
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testLoopbackLinkNeverSends() async {
        let local = DevicePairingLink(code: "ABC234", server: KimaServer(baseURL: URL(string: "http://localhost:3030")!))
        let vm = makeVM(.link(local))
        vm.confirm()
        await vm.linkTask?.value
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testScannerHintsAndAcceptance() {
        let vm = makeVM(.scan)
        XCTAssertFalse(vm.scanned("https://example.com"))
        XCTAssertEqual(vm.scanHint, "that isn't a kima code.")
        XCTAssertEqual(vm.step, .scanning)
        XCTAssertTrue(vm.scanned("kima://link?code=ABC234&server=https%3A%2F%2Flink.example%3A8443"))
        XCTAssertEqual(vm.step, .confirm(link))
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testInvalidLinkShowsAnError() {
        let vm = makeVM(.invalid)
        XCTAssertEqual(vm.step, .failed(message: "that isn't a valid kima link.", retry: nil))
    }
}
