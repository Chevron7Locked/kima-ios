import XCTest
@testable import Kima

/// Sources the current test started, held strongly on purpose: the keeper loop captures its
/// owner weakly, so this registry is the home that keeps one alive until `quiesce()` stops it —
/// like `startedEnvs` in AppEnvironmentBootstrapTests. XCTest runs tests one at a time, so only
/// one test's sources are ever in here.
nonisolated(unsafe) private var startedSources: [StreamSource] = []

/// The stream source (ticket 13): the one module that answers playable URLs for playback — it
/// mints the short-lived stream ticket, caches it until near its half-life, keeps it warm ahead
/// of taps, and drops it when credentials rotate. Seam: `StreamSource(server:client:)` over a
/// stubbed client with time injected through the module's clock seam; everything observed as
/// requests recorded by the stub transport. The renewal schedule is asserted, never waited out.
@MainActor
final class StreamSourceTests: KeychainLoginTestCase {
    let server = KimaServer(baseURL: URL(string: "https://stub.test")!)
    let jwt = "SECRET.LOGIN.JWT"

    // MARK: - Playable URL answers

    func testFirstAskMintsTheTicketAndTheUrlCarriesItNotTheJwt() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"ticket":"st-9","expiresIn":3600}"#.utf8)) }
        let source = StreamSource(server: server, client: .stubbed(credential: .jwt(jwt)))
        guard case .url(let url) = await source.playableURL(trackId: "trk-1") else {
            return XCTFail("expected a playable URL from a ticketed server")
        }
        XCTAssertEqual(url.path, "/api/library/tracks/trk-1/stream")
        XCTAssertEqual(url.query, "token=st-9")
        XCTAssertFalse(url.absoluteString.contains(jwt),
                       "the login token never rides a stream URL when the server takes tickets")
    }

    func testTicketIsCachedUntilHalfItsLifeAndRenewedAfter() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"ticket":"st-9","expiresIn":3600}"#.utf8)) }
        let time = VirtualTime()
        let source = StreamSource(server: server, client: .stubbed(credential: .jwt(jwt)), clock: time.clock)

        _ = await source.playableURL(trackId: "trk-1")
        XCTAssertEqual(ticketMints, 1)

        time.advance(1799)   // a hair inside the half-life of a 3600 s ticket
        _ = await source.playableURL(trackId: "trk-1")
        XCTAssertEqual(ticketMints, 1, "a cached ticket answers until its renewal point")

        time.advance(2)      // past 1800 = TTL/2
        _ = await source.playableURL(trackId: "trk-1")
        XCTAssertEqual(ticketMints, 2, "past the renewal point the next ask re-mints")
    }

    /// The mint-side half of the renewal schedule: a ticket with less than a minute of life left
    /// is renewed even while it's younger than half its TTL — that floor exists once, in the module.
    func testTheRenewalPointNeverSitsCloserThanSixtySecondsToExpiry() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"ticket":"st-9","expiresIn":90}"#.utf8)) }
        let time = VirtualTime()
        let source = StreamSource(server: server, client: .stubbed(credential: .jwt(jwt)), clock: time.clock)

        _ = await source.playableURL(trackId: "trk-1")
        time.advance(40)   // past expiry−60 (30 s in), still inside the 45 s half-life of a 90 s ticket
        _ = await source.playableURL(trackId: "trk-1")
        XCTAssertEqual(ticketMints, 2, "a near-expiry ticket is never risked, however young it is")
    }

    func testConcurrentAsksShareOneInFlightMint() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"ticket":"st-9","expiresIn":3600}"#.utf8)) }
        let source = StreamSource(server: server, client: .stubbed(credential: .jwt(jwt)))
        async let a = source.playableURL(trackId: "trk-a")
        async let b = source.playableURL(trackId: "trk-b")
        _ = await (a, b)
        XCTAssertEqual(ticketMints, 1, "an ask that arrives while a mint is in flight joins it, like the refresh task before it")
    }

    // MARK: - Preview clip answers (ticket 14)

    /// The page preview rows ask this source too (album, browse-playlist, artist): the server's
    /// preview proxy path carrying a ticket — no page mints or assembles any of it.
    func testPreviewAnswerCarriesTheTicketOnTheProxyPath() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"ticket":"st-9","expiresIn":3600}"#.utf8)) }
        let source = StreamSource(server: server, client: .stubbed(credential: .jwt(jwt)))
        guard case .url(let url) = await source.previewURL(artistName: "ABBA", trackTitle: "Dancing Queen") else {
            return XCTFail("expected a preview URL from a ticketed server")
        }
        XCTAssertEqual(url.absoluteString,
                       "https://stub.test/api/artists/preview/ABBA/Dancing%20Queen/stream?token=st-9",
                       "the title must ride percent-encoded in the path, with the ticket as the only query item")
        XCTAssertFalse(url.absoluteString.contains(jwt),
                       "the login token never rides a preview URL either")
    }

    func testPreviewAndPlayAsksShareOneCachedMint() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"ticket":"st-9","expiresIn":3600}"#.utf8)) }
        let source = StreamSource(server: server, client: .stubbed(credential: .jwt(jwt)))
        let clip = await source.previewURL(artistName: "ABBA", trackTitle: "Gimme").url
        XCTAssertNotNil(clip, "the preview answer should have landed a URL")
        _ = await source.playableURL(trackId: "trk-1")
        XCTAssertEqual(ticketMints, 1,
                       "a preview tap rides the keeper's warm ticket — the head start pages keep for free")
    }

    func testPreviewAnswerOnATicketlessServerRidesTheLoginToken() async {
        storeLogin(jwt, for: server)
        StubURLProtocol.handler = { _ in (404, Data()) }
        let source = StreamSource(server: server, client: .stubbed(credential: .jwt(jwt)))
        guard case .url(let url) = await source.previewURL(artistName: "ABBA", trackTitle: "Gimme") else {
            return XCTFail("a ticketless server still answers previews with its login token")
        }
        XCTAssertEqual(url.query, "token=\(jwt)")
    }

    /// The pages' fallback contract: a mint that fails answers `noTicket` — the page then offers
    /// its payload's raw link (or nothing), and no all-scope token rides the clip URL.
    func testFailedPreviewMintAnswersNoTicketForThePagesToFallBackOn() async {
        StubURLProtocol.handler = { _ in (500, Data()) }
        let source = StreamSource(server: server, client: .stubbed(credential: .jwt(jwt)))
        assertNoAnswer(await source.previewURL(artistName: "ABBA", trackTitle: "Gimme"))
    }

    // MARK: - The established fallback, and its limits

    /// A server without the ticket endpoint (404): the login JWT is the only stream credential it
    /// accepts, so it rides the URL — for THIS server's login and nobody else's.
    func testTicketlessServerFallsBackToItsOwnLoginToken() async {
        storeLogin(jwt, for: server)
        StubURLProtocol.handler = { _ in (404, Data()) }
        let source = StreamSource(server: server, client: .stubbed(credential: .jwt(jwt)))
        guard case .url(let url) = await source.playableURL(trackId: "trk-1") else {
            return XCTFail("a ticketless server still gets a playable URL via the login token")
        }
        XCTAssertEqual(url.query, "token=\(jwt)")
    }

    func testTicketlessServerNeverFallsBackToAnotherServersToken() async {
        storeLogin(jwt, for: KimaServer(baseURL: URL(string: "https://other.test")!))
        StubURLProtocol.handler = { _ in (404, Data()) }
        let source = StreamSource(server: server, client: .stubbed(credential: .jwt(jwt)))
        assertNoAnswer(await source.playableURL(trackId: "trk-1"))
    }

    /// Any other failure answers no URL at all — the login token never leaks into stream/proxy logs
    /// as an all-scope credential just because a mint hiccuped.
    func testFailedMintsProduceNoAnswer() async {
        for (label, client) in [
            ("500", KimaAPIClient.stubbed(credential: .jwt(jwt))),
            ("503", KimaAPIClient.stubbed(credential: .jwt(jwt))),
            ("401", KimaAPIClient.stubbed(credential: .apiKey("k"))),   // apiKey: no refresh round trip
            ("malformed 200", KimaAPIClient.stubbed(credential: .jwt(jwt))),
        ] {
            StubURLProtocol.reset()
            storeLogin(jwt, for: server)
            StubURLProtocol.handler = { _ in
                switch label {
                case "500": return (500, Data())
                case "503": return (503, Data())
                case "401": return (401, Data())
                default: return (200, Data("{}".utf8))
                }
            }
            assertNoAnswer(await StreamSource(server: server, client: client).playableURL(trackId: "trk-1"), label)
        }
    }

    func testUnreachableServerProducesNoAnswer() async {
        storeLogin(jwt, for: server)
        let client = KimaAPIClient(server: server, credential: .jwt(jwt),
                                   sessions: StubSessionFactory(protocolClasses: [FailingURLProtocol.self]))
        assertNoAnswer(await StreamSource(server: server, client: client).playableURL(trackId: "trk-1"))
    }

    func testDroppingTheTicketMakesTheNextAskMintAFreshOne() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"ticket":"st-9","expiresIn":3600}"#.utf8)) }
        let source = StreamSource(server: server, client: .stubbed(credential: .jwt(jwt)))
        _ = await source.playableURL(trackId: "trk-1")
        source.dropTicket()   // what a mid-stream rebuild does first: the server just rejected this ticket
        _ = await source.playableURL(trackId: "trk-1")
        XCTAssertEqual(ticketMints, 2, "a dropped ticket is never reused, however fresh it was")
    }

    // MARK: - Warm keeper and rotation-drop

    func testStartingMintsAheadOfTheFirstTapAndSleepsToTheRenewalPoint() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"ticket":"st-9","expiresIn":14400}"#.utf8)) }
        let time = VirtualTime()
        _ = startedSource(clock: time.clock)
        await waitUntil { ticketMints == 1 && !time.sleeps.isEmpty }
        XCTAssertEqual(ticketMints, 1, "the head start is one mint at sign-in — no tap needed")
        XCTAssertEqual(time.sleeps, [.seconds(7200)],
                       "the keeper sleeps exactly to the cache's renewal point: TTL/2 of a 4-hour ticket")
    }

    /// The schedule floor stated once inside the module: a pathological tiny TTL whose renewal
    /// point is already past must not spin the loop.
    func testKeeperFloorOnATinyTicketLifetime() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"ticket":"st-9","expiresIn":40}"#.utf8)) }
        let time = VirtualTime()
        _ = startedSource(clock: time.clock)
        await waitUntil { ticketMints == 1 && !time.sleeps.isEmpty }
        XCTAssertEqual(time.sleeps, [.seconds(30)], "never below 30 s, whatever the server's TTL says")
    }

    /// A server without the ticket endpoint caches nothing, so the keeper re-checks on a fixed
    /// five-minute rhythm instead of never (nil) or instantly (busy loop).
    func testKeeperRhythmOnATicketlessServer() async {
        storeLogin(jwt, for: server)
        StubURLProtocol.handler = { _ in (404, Data()) }
        let time = VirtualTime()
        _ = startedSource(clock: time.clock)
        await waitUntil { ticketMints == 1 && !time.sleeps.isEmpty }
        XCTAssertEqual(time.sleeps, [.seconds(300)])
    }

    func testKeeperStopsWhenTheServerRefuses() async {
        StubURLProtocol.handler = { _ in (500, Data()) }
        let time = VirtualTime()
        _ = startedSource(clock: time.clock)
        await waitUntil { ticketMints == 1 }
        try? await Task.sleep(for: .milliseconds(100))   // a retry-forever loop would have piled up by now
        XCTAssertEqual(ticketMints, 1, "a refused mint stops the keeper; the play path mints on demand")
        XCTAssertTrue(time.sleeps.isEmpty)
    }

    func testTokenRotationDropsTheTicketAndRemakesItWarm() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"ticket":"st-9","expiresIn":14400}"#.utf8)) }
        let time = VirtualTime()
        _ = startedSource(clock: time.clock)
        await waitUntil { ticketMints == 1 && !time.sleeps.isEmpty }
        NotificationCenter.default.post(name: .kimaAccessTokenRotated, object: nil)
        await waitUntil { ticketMints == 2 }
        XCTAssertEqual(ticketMints, 2,
                       "the warm ticket follows the new token now — not when the old sleep ends hours later")
    }

    func testRotationAfterStopDoesNothing() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"ticket":"st-9","expiresIn":14400}"#.utf8)) }
        let time = VirtualTime()
        let source = startedSource(clock: time.clock)
        await waitUntil { ticketMints == 1 && !time.sleeps.isEmpty }
        source.stop()
        NotificationCenter.default.post(name: .kimaAccessTokenRotated, object: nil)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(ticketMints, 1, "a stopped source mints for no session, rotated tokens included")
    }

    /// Stop every keeper this test started and drain its last in-flight mint, so no stray
    /// request lands inside the next test's zero-count assertion; the base then wipes HTTP state
    /// and restores the simulator's login.
    override func quiesce() async {
        let sources = startedSources
        startedSources.removeAll()
        sources.forEach { $0.stop() }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    // MARK: - Helpers

    /// A source started on the stub client, homed in `startedSources` until `quiesce()` stops it.
    private func startedSource(clock: StreamClock) -> StreamSource {
        let source = StreamSource(server: server, client: .stubbed(credential: .jwt(jwt)), clock: clock)
        startedSources.append(source)
        source.start()
        return source
    }

    /// Mints this test has driven: the only request the cache changes the count of.
    var ticketMints: Int { StubURLProtocol.requests.filter { $0.url?.path == "/api/auth/stream-ticket" }.count }

    /// Writes a login for `server` (the fallback reads it back from the Keychain, like production).
    func storeLogin(_ token: String, for server: KimaServer) {
        XCTAssertTrue(KeychainStore.setCredential(token, for: KeychainStore.accessToken, server: server))
    }

    func assertNoAnswer(_ answer: StreamSource.Answer, _ label: String = "",
                        file: StaticString = #filePath, line: UInt = #line) {
        guard case .noTicket = answer else {
            return XCTFail("expected no ticket\(label.isEmpty ? "" : " (\(label))"), got \(answer)", file: file, line: line)
        }
    }
}

/// Virtual time for the clock seam: `advance` steps the source's world for cache tests, and the
/// injected `sleep` records the keeper's schedule while stepping this world to the wake-up point
/// and ending that cycle — so one start shows exactly one recorded sleep and every schedule is
/// asserted as an exact number instead of waited out. Mutated only on the main actor — the
/// source and these tests share it (same posture as `SignalCounter` in SSEManagerReconnectTests).
private final class VirtualTime: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_763_100_000)   // a fixed instant; schedules are relative
    private(set) var sleeps: [Duration] = []

    var clock: StreamClock {
        StreamClock(now: { [self] in now }, sleep: { [self] delay in
            sleeps.append(delay)
            now = now.addingTimeInterval(TimeInterval(delay.components.seconds))   // whole seconds only, as the module spells them
            throw CancellationError()   // the seam's contract: a throwing sleep ends the keeper loop
        })
    }

    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
