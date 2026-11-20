import XCTest
@testable import Kima

/// The connect screen's failure copy names what is wrong with the typed address (GitHub #1).
/// Every request fails at the transport with the error under test; nothing leaves the machine.
@MainActor
final class ConnectViewModelTests: XCTestCase {

    override func tearDown() {
        FailingURLProtocol.failure = URLError(.notConnectedToInternet)
        super.tearDown()
    }

    private func failure(typing text: String, failingWith code: URLError.Code) async -> ConnectViewModel.Phase {
        FailingURLProtocol.failure = URLError(code)
        let vm = ConnectViewModel(makeClient: { server, _ in
            KimaAPIClient(server: server, sessions: StubSessionFactory(protocolClasses: [FailingURLProtocol.self]))
        })
        vm.urlText = text
        await vm.check()
        return vm.phase
    }

    func testUnknownNameSaysSo() async {
        let phase = await failure(typing: "http://kima.lan:3030", failingWith: .cannotFindHost)
        XCTAssertEqual(phase, .failed("couldn't find a server with that name. check the address."))
    }

    func testNothingListeningPointsAtThePort() async {
        let phase = await failure(typing: "192.168.1.20:3030", failingWith: .cannotConnectToHost)
        XCTAssertEqual(phase, .failed("nothing answered at that address. check the port and that the server is running."))
    }

    func testTimeoutSaysTheServerWasSlow() async {
        let phase = await failure(typing: "192.168.1.20:3030", failingWith: .timedOut)
        XCTAssertEqual(phase, .failed("the server took too long to answer. check the address and your connection."))
    }

    func testOfflineKeepsTheAppWideLine() async {
        let phase = await failure(typing: "192.168.1.20:3030", failingWith: .notConnectedToInternet)
        XCTAssertEqual(phase, .failed("you're offline. check your connection."))
    }

    /// An http-only server reached on the https the app picked for a dotted name answers the TLS
    /// hello with plain text (-1200) or nothing listens (-1004): the guessed scheme is the cause.
    func testGuessedHttpsFailingSuggestsTypingHttp() async {
        let hint = "couldn't connect over https. if your server uses plain http, type http:// before the address."
        for code: URLError.Code in [.secureConnectionFailed, .cannotConnectToHost] {
            let phase = await failure(typing: "kima.tail1234.ts.net:3030", failingWith: code)
            XCTAssertEqual(phase, .failed(hint), "\(code)")
        }
    }

    /// A certificate error means a real https server answered: the hint would hide the actual reason.
    func testGuessedHttpsWithABadCertificateKeepsTheCertificateLine() async {
        let phase = await failure(typing: "kima.example.com", failingWith: .serverCertificateUntrusted)
        XCTAssertEqual(phase, .failed("the server's certificate isn't trusted. check its https setup, or use http on your local network."))
    }

    func testTypedHttpsKeepsTheCertificateLine() async {
        let phase = await failure(typing: "https://kima.example.com", failingWith: .serverCertificateUntrusted)
        XCTAssertEqual(phase, .failed("the server's certificate isn't trusted. check its https setup, or use http on your local network."))
    }
}
