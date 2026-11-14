import XCTest
@testable import Kima

/// Managers the current test started, held strongly on purpose: the stream task captures `self`
/// weakly (production owns managers via AppEnvironment), so without a home here ARC releases a
/// manager between `start()` and the main actor running its queued Task, and the loop's
/// `guard let self` ends it before a single request. File-scope and nonisolated(unsafe) because
/// `tearDown` runs off the main actor; XCTest runs tests one at a time, so only one
/// test's managers are ever in here. Owning the manager, and cancelling it at test end, are
/// the test's job — production's owner (AppEnvironment) has neither duty here.
nonisolated(unsafe) private var startedManagers: [SSEManager] = []

/// The reconnect loop (ticket 09) under unit test, driven through the session-factory seam:
/// `SSEManager(sessions: StubSessionFactory())` plus a stubbed client means the ticket mint and
/// the stream GET both answer from canned responses — backoff growth, ticket-per-connection,
/// terminal auth and the hung-socket timeouts stop being coverage-by-production-server.
/// Seam: `start(client:server:)` in, observable state + `StubURLProtocol.requests` out; the
/// backoff pause is watched through an injected delay instead of wall-clock seconds.
@MainActor
final class SSEManagerReconnectTests: XCTestCase {

    override func setUp() { StubURLProtocol.reset() }

    override func tearDown() async throws {
        // Kill every loop this test started, and drain its last in-flight request, before the
        // next test begins — XCTest awaits tearDown, which is exactly why cancellation lives
        // here and not in an addTeardownBlock: a no-delay-backoff manager still alive when the
        // next test installs its handler would mint through it mid-assertion, and one GET that
        // was already in flight at cancel time lands after the next setUp's reset. Settle the
        // strays, then wipe them, so nothing crosses the test boundary.
        let managers = startedManagers
        startedManagers.removeAll()
        await MainActor.run { managers.forEach { $0.teardown() } }
        try? await Task.sleep(nanoseconds: 50_000_000)
        StubURLProtocol.reset()
    }

    // MARK: - Helpers

    /// Records the delays the loop asks for. An actor because the seam's type is `@Sendable` —
    /// recording stays safe whatever isolation a caller of the seam has.
    private actor DurationRecorder {
        private(set) var durations: [Duration] = []
        func record(_ delay: Duration) { durations.append(delay) }
        var count: Int { durations.count }
    }

    /// Counts sign-out signals. Mutated only on the main thread: the observer delivers
    /// synchronously on the posting thread (the main-actor loop) and every read runs on the
    /// main actor.
    private final class SignalCounter: @unchecked Sendable {
        var count = 0
    }

    /// A manager wired to the stubs and already streaming: created, backoff injected (nil keeps
    /// the production sleep), started against the stub server, kept alive by `startedManagers`
    /// until `tearDown` cancels it. Callers keep only their handler — the data difference.
    @discardableResult
    private func startedManager(
        credential: KimaCredential = .jwt("test"),
        backoffDelay: (@Sendable (Duration) async -> Void)? = nil
    ) -> SSEManager {
        let sse = SSEManager(sessions: StubSessionFactory())
        if let backoffDelay { sse.backoffDelay = backoffDelay }
        startedManagers.append(sse)   // strong home — see the file-level declaration
        sse.start(client: .stubbed(credential: credential),
                  server: KimaServer(baseURL: URL(string: "https://stub.test")!))
        return sse
    }

    /// The stream GETs the loop opened (path is exactly /api/events; the mint ends in /ticket).
    private var streamRequests: [URLRequest] {
        StubURLProtocol.requests.filter { $0.url?.path == "/api/events" }
    }

    /// A handler where the mint answers with a fresh ticket per call — except the first
    /// `mintFailures`, which fail transiently — and the stream answers `streamStatus` with
    /// `streamBody`.
    private func stubStream(mintFailures: Int = 0, streamStatus: Int = 200, streamBody: String = "") {
        var mintCount = 0
        StubURLProtocol.handler = { req in
            switch req.url?.path {
            case "/api/events/ticket":
                mintCount += 1
                guard mintCount > mintFailures else { return (500, Data()) }
                return (200, Data("{\"ticket\":\"tk-\(mintCount)\"}".utf8))
            case "/api/events":
                return (streamStatus, Data(streamBody.utf8))
            default:
                return (404, Data())
            }
        }
    }

    /// The terminal-auth contract against a handler the test already installed: sign-out is
    /// announced exactly once — counted by an observer, not a one-shot expectation that stops
    /// listening after the first — and the loop stops dead. A loop still alive would hammer
    /// hundreds of mints inside the quiet window with the injected no-delay backoff.
    /// `expectedStreamAttempts`: 0 = died at the mint; 1 = opened the stream once, died there.
    private func assertSignalledOnceThenStopped(
        credential: KimaCredential = .jwt("test"),
        expectedStreamAttempts: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        let signals = SignalCounter()
        // queue: nil — the block runs synchronously on the posting thread (the main-actor loop),
        // so counting can't depend on the main run loop being spun under an async test.
        let token = NotificationCenter.default.addObserver(
            forName: .kimaSSEAuthFailed, object: nil, queue: nil) { _ in signals.count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        startedManager(credential: credential, backoffDelay: { _ in })

        await waitUntil { signals.count >= 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(signals.count, 1, "sign-out must be announced exactly once", file: file, line: line)
        XCTAssertEqual(StubURLProtocol.posts(to: "/events/ticket").count, 1,
                       "an auth rejection must stop reconnecting, not mint again", file: file, line: line)
        XCTAssertEqual(streamRequests.count, expectedStreamAttempts,
                       "an auth rejection must stop reconnecting, not re-open the stream", file: file, line: line)
    }

    // MARK: - The stream rides the stub session

    /// The tracer: `URLSession.bytes` through the factory's stub adapter delivers real frames —
    /// a minted ticket reaches the stream URL and a parsed event bumps its tick.
    func testStreamOpensThroughTheStubSessionAndEventsFlow() async {
        stubStream(streamBody: "data: {\"type\":\"download:progress\"}\n\n")
        let sse = startedManager()   // production backoff: no reconnect races the assertions

        await waitUntil { sse.downloadTick >= 1 }
        XCTAssertEqual(sse.downloadTick, 1, "a frame on the stub stream must reach the dispatcher")
        let stream = streamRequests.first
        XCTAssertEqual(stream?.url?.query?.contains("ticket=tk-1"), true,
                       "the stream URL must carry the freshly minted ticket")
    }

    /// A stream the server closes is not the end: the loop reconnects, and the second
    /// connection mints its own ticket — tickets are single-use, so reuse would be a silent
    /// 401 loop against a real server. Watched as the settled first two stream GETs.
    func testDroppedStreamReconnectsWithAFreshTicket() async {
        stubStream()   // mint answers tk-n; the stream answers 200 and closes at once
        startedManager(backoffDelay: { _ in })   // instant retry: reconnects arrive without waits

        await waitUntil { self.streamRequests.count >= 2 }
        let tickets = streamRequests.prefix(2).map {
            URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "ticket" })?.value ?? "?"
        }
        XCTAssertEqual(Array(tickets), ["tk-1", "tk-2"],
                       "each connection must ride its own freshly minted ticket")
    }

    // MARK: - Backoff schedule

    /// A stream that can never connect backs off by doubling from 1 s per failed attempt and
    /// stops growing at the 30 s cap — the schedule the loop promises, asserted as written
    /// literals, watched through the injected-delay seam instead of wall-clock seconds.
    func testBackoffDoublesFromOneSecondAndCapsAtThirty() async {
        StubURLProtocol.handler = { _ in (500, Data()) }   // every mint fails: transient forever
        let recorder = DurationRecorder()
        startedManager(backoffDelay: { await recorder.record($0) })

        await waitUntil { await recorder.count >= 6 }
        // The prefix only: with the delay injected away the loop retries instantly, so later
        // entries keep arriving — the first six are settled once written.
        let recorded = await recorder.durations
        XCTAssertEqual(Array(recorded.prefix(6)),
                       [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30)],
                       "backoff must double from 1 s per failed attempt and cap at 30 s")
    }

    /// The schedule's other half: a connection that succeeds resets the doubling, so the gap
    /// after the next drop is one second again — not the 2 s a blind counter would sleep past
    /// a healthy stream that lived for an hour before dying.
    func testSuccessfulConnectionResetsTheBackoff() async {
        stubStream(mintFailures: 1)   // first mint fails transiently; then connects, then drops
        let recorder = DurationRecorder()
        startedManager(backoffDelay: { await recorder.record($0) })

        await waitUntil { await recorder.count >= 2 }
        let recorded = await recorder.durations
        XCTAssertEqual(Array(recorded.prefix(2)), [.seconds(1), .seconds(1)],
                       "one failure then one success must sleep 1 s, not the doubled 2 s")
    }

    // MARK: - Hung-socket timeouts

    /// Where the hung-socket story is tested (ticket 09): `requestTimeout` 600 s is the max gap
    /// between bytes — longer than the server's SSE keepalive, so only genuine silence trips it,
    /// and that error is what sets the reconnect loop going; `resourceTimeout` 86 400 s forces a
    /// clean reconnect once a day however healthy the socket looks. Finite values are the point:
    /// without them a silently-dead connection (server gone, no FIN) would hang forever instead
    /// of reconnecting, and the OS gets to reclaim both.
    func testTheStreamSessionCarriesTheHungSocketTimeouts() {
        let config = SSEManager(sessions: StubSessionFactory()).sseSession.configuration
        XCTAssertEqual(config.timeoutIntervalForRequest, 600, "10 min of silence must error out and reconnect")
        XCTAssertEqual(config.timeoutIntervalForResource, 86_400, "one day caps a stream's lifetime")
    }

    // MARK: - Terminal auth

    /// A 401 or 403 on the stream endpoint means the ticket was rejected or the token revoked:
    /// the loop stops reconnecting and signals the shell exactly once — an over-loud signal
    /// would toast-spam, a silent one leaves live updates dying unnoticed. Both statuses ride
    /// the same guard in the loop, so both are exercised here.
    func testStreamAuthRejectionSignalsSignOutOnceAndStops() async {
        for status in [401, 403] {
            StubURLProtocol.reset()
            stubStream(streamStatus: status)
            await assertSignalledOnceThenStopped(expectedStreamAttempts: 1)
        }
    }

    /// The mint's side of the same ruling: a terminal answer from `POST /api/events/ticket` —
    /// 401 (`.unauthorized`) or 403 (`http(403)`) — is the token being expired or revoked.
    /// Sign-out is announced once and the stream is never opened, because there is no ticket to
    /// open it with. (API-key credential: its 401 comes back directly, without the refresh
    /// round-trip that would blur what "terminal" means.)
    func testAuthRejectedMintSignalsSignOutOnceAndNeverOpensTheStream() async {
        for status in [401, 403] {
            StubURLProtocol.reset()
            StubURLProtocol.handler = { _ in (status, Data()) }
            await assertSignalledOnceThenStopped(credential: .apiKey("k"), expectedStreamAttempts: 0)
        }
    }
}
