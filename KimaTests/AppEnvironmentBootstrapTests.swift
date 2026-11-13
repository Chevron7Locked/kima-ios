import XCTest
@testable import Kima

/// Environments the current test built, held strongly on purpose: the running loops capture
/// their owners weakly, so this registry is the home that keeps them alive until `quiesce()`
/// stops them — like `startedManagers` in SSEManagerReconnectTests. XCTest runs tests one at a
/// time, so only one test's environments are ever in here; production's owner (RootView) has
/// neither duty here.
nonisolated(unsafe) private var startedEnvs: [AppEnvironment] = []

/// The bootstrap split (ticket 12): constructing the environment bag must be inert, and one
/// start on the bootstrap module must open — and one stop close — the signed-in session's whole
/// network lifecycle. Seam: `AppEnvironment(server:sessions:)` in, `bootstrap.start()/stop()`,
/// everything observed as requests recorded by the stub adapter — a login against a fake host
/// where every endpoint answers from canned responses. On-device behavior these pin: previews
/// that build an environment never go live; sign-out leaves no zombie stream behind.
@MainActor
final class AppEnvironmentBootstrapTests: KeychainLoginTestCase {
    private let server = KimaServer(baseURL: URL(string: "https://bootstrap.test")!)

    override func setUpWithError() throws {
        try super.setUpWithError()   // HTTP reset, login snapshot, clean slate, hard writability assert
        UserDefaults.standard.set(server.baseURL.absoluteString, forKey: ServerURLStore.key)
        XCTAssertTrue(KeychainStore.setCredential("live-token", for: KeychainStore.accessToken, server: server))
        // No refresh token is stored: failures propagate instead of looping.
        StubURLProtocol.handler = Self.sessionHandler
    }

    /// Stop every lifecycle this test started and drain its last in-flight requests, so no
    /// stray mint lands inside the next test's zero-count assertion; the base then wipes HTTP
    /// state and restores the simulator's login (its stored address with it).
    override func quiesce() async {
        let envs = startedEnvs
        startedEnvs.removeAll()
        envs.forEach { $0.bootstrap.stop() }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    // MARK: - Helpers

    /// A signed-in session's endpoints, canned: event-ticket and stream-ticket mints succeed,
    /// the stream answers and closes (its reconnect then waits on backoff), the notification
    /// list is empty, and there is no saved playback state yet.
    static func sessionHandler(_ req: URLRequest) -> (status: Int, body: Data) {
        switch req.url?.path {
        case "/api/events/ticket": return (200, Data(#"{"ticket":"ev-1"}"#.utf8))
        case "/api/auth/stream-ticket": return (200, Data(#"{"ticket":"st-1","expiresIn":14400}"#.utf8))
        case "/api/events": return (200, Data())
        case "/api/notifications": return (200, Data("[]".utf8))
        default: return (404, Data())   // incl. /api/playback-state: nothing saved yet
        }
    }

    /// Builds an environment through the stub adapter and gives it a home until `tearDown`
    /// stops it. Callers keep only what they assert about.
    private func makeEnv() -> AppEnvironment {
        let env = AppEnvironment(server: server, sessions: StubSessionFactory())
        startedEnvs.append(env)
        return env
    }

    /// Polls until `condition` holds or the deadline passes; the lifecycle tasks run on the main
    /// actor cooperatively, so awaiting here lets them advance.
    private func waitUntil(_ timeout: TimeInterval = 2, _ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private var paths: [String] { StubURLProtocol.requests.compactMap(\.url?.path) }

    /// The five paths one open lifecycle must show: the warm stream-ticket keeper, the event
    /// stream's own per-connection mint, the stream itself, the initial notification refresh,
    /// and sync hydration.
    private static let lifecyclePaths: Set<String> = [
        "/api/auth/stream-ticket", "/api/events/ticket", "/api/events",
        "/api/notifications", "/api/playback-state",
    ]

    /// Awaits until every lifecycle path has been requested at least once.
    private func waitLifecycleOpen() async {
        let opened = Self.lifecyclePaths
        await waitUntil { opened.isSubset(of: Set(self.paths)) }
    }

    // MARK: - Tests

    /// The ticket's proof: constructing a session against a fake host makes zero connection
    /// attempts. Today the init itself mints a ticket, opens the event stream, mutates the
    /// shared image cache, and installs an observer — this test is the wall that stays up.
    func testConstructingTheBagConnectsToNothing() async {
        let env = makeEnv()
        try? await Task.sleep(nanoseconds: 200_000_000)   // any leaked loop would have asked by now
        XCTAssertTrue(StubURLProtocol.requests.isEmpty,
                      "building the bag must not touch the network: \(paths)")
        _ = env   // silence unused — the env's liveness IS the subject
    }

    /// One call opens what init used to open across five statements: the ticket keeper mints,
    /// sync hydrates, the event stream takes its own ticket and connects, and the notification
    /// list refreshes. Nothing else starts a signed-in session's lifecycle.
    func testStartOpensTheWholeLifecycle() async {
        let env = makeEnv()
        env.bootstrap.start()
        await waitLifecycleOpen()
        XCTAssertTrue(Self.lifecyclePaths.isSubset(of: Set(paths)), "start() opened only: \(paths)")
    }

    /// Starting is idempotent: a second window joining the live environment calls start again,
    /// and that must open nothing new — no rehydrated sync poll, no second stream.
    func testStartTwiceOpensOneLifecycle() async {
        let env = makeEnv()
        // Long backoff keeps the stubbed stream (which closes at once) from reconnecting inside
        // the counting windows; a double start's duplicates would still show immediately.
        env.events.backoffDelay = { _ in try? await Task.sleep(for: .seconds(600)) }
        env.bootstrap.start()
        await waitLifecycleOpen()
        try? await Task.sleep(nanoseconds: 300_000_000)   // settle to steady state (all loops sleep long now)
        let afterFirst = StubURLProtocol.requests.count
        env.bootstrap.start()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(StubURLProtocol.requests.count, afterFirst,
                       "second start opened something new: \(paths.suffix(8))")
    }

    /// Stop must end the loops for good — a stopped session asks for nothing more (with backoff
    /// at zero a zombie stream would hammer, not whisper) — and it stays ended: `start()` after
    /// `stop()` cannot revive a signed-out session's lifecycle; a re-login builds a fresh env.
    func testStopQuiescesAndStaysStopped() async {
        let env = makeEnv()
        env.events.backoffDelay = { _ in }   // zero delay: a live loop reconnects instantly
        env.bootstrap.start()
        await waitUntil { self.paths.contains("/api/events") }
        env.bootstrap.stop()
        try? await Task.sleep(nanoseconds: 200_000_000)   // land the one attempt already in flight, then count
        let afterStop = StubURLProtocol.requests.count
        env.bootstrap.stop()                                // idempotent
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(StubURLProtocol.requests.count, afterStop,
                       "a stopped lifecycle asked for something: \(paths.suffix(8))")
        env.bootstrap.start()                               // terminal: stopped stays stopped
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(StubURLProtocol.requests.count, afterStop,
                       "start after stop revived the lifecycle")
    }

    /// The rotation observer belongs to a running lifecycle: rotating the token before start
    /// remints nothing (construction installs no observer), and after start it re-warms the
    /// ticket at once — the keeper's own sleep runs to half the ticket's lifetime, hours.
    func testTokenRotationRemintsOnlyWhileRunning() async {
        let env = makeEnv()
        NotificationCenter.default.post(name: .kimaAccessTokenRotated, object: nil)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty,
                      "a session that never started observed a rotation: \(paths)")

        env.bootstrap.start()
        await waitUntil { self.paths.contains("/api/auth/stream-ticket") }
        let before = StubURLProtocol.posts(to: "/auth/stream-ticket").count
        NotificationCenter.default.post(name: .kimaAccessTokenRotated, object: nil)
        await waitUntil { StubURLProtocol.posts(to: "/auth/stream-ticket").count > before }
        XCTAssertEqual(StubURLProtocol.posts(to: "/auth/stream-ticket").count, before + 1,
                       "one rotation re-warms exactly one ticket")
    }
}
