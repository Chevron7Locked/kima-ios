import XCTest
@testable import Kima

@MainActor
final class VibeCancellationTests: XCTestCase {
    override func setUp() { StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset() }

    private func controller() -> PlaybackController {
        PlaybackController(server: KimaServer(baseURL: URL(string: "http://test.local")!))
    }

    // MARK: replace question

    func testCancellingTheAskerAnswersNoAndClosesThePrompt() async {
        let c = controller()
        c.queueOrigin = .songPath
        let asker = Task { await c.confirmVibeReplace(with: .blend) }
        await waitUntil(message: "the replace question never opened") { c.vibeReplacePrompt != nil }
        asker.cancel()
        let answer = await asker.value
        XCTAssertFalse(answer)
        XCTAssertNil(c.vibeReplacePrompt)
        XCTAssertNil(c.vibeReplaceContinuation)
    }

    func testAskingWhileAlreadyCancelledNeverOpensAPrompt() async {
        let c = controller()
        c.queueOrigin = .songPath
        let asker = Task { () -> Bool in
            while !Task.isCancelled { await Task.yield() }
            return await c.confirmVibeReplace(with: .blend)
        }
        asker.cancel()
        let answer = await asker.value
        XCTAssertFalse(answer)
        XCTAssertNil(c.vibeReplacePrompt)
    }

    func testClosingTheMapCancelsWhatItLaunched() async {
        let c = controller()
        c.queueOrigin = .songPath
        let vm = VibeMapViewModel()
        var answer: Bool?
        vm.launch { answer = await c.confirmVibeReplace(with: .playSimilar) }
        await waitUntil(message: "the replace question never opened") { c.vibeReplacePrompt != nil }
        vm.cancelOperations()
        await waitUntil { answer != nil }
        XCTAssertEqual(answer, false)
        XCTAssertNil(c.vibeReplacePrompt)
    }

    // MARK: vibe button

    private let similarJSON = Data(#"{"sourceTrackId":"a","tracks":[{"id":"x","title":"t","duration":10,"album":{"id":"al","title":"x"},"artist":{"id":"ar","name":"n"},"similarity":0.5}]}"#.utf8)

    /// Starts the vibe button's fetch and, while it is in flight, has the map start a song path.
    private func toggleOvertakenBySongPath(_ c: PlaybackController) async throws -> Task<Void, Never> {
        c.queue = [try Track.fixture("a")]
        c.currentIndex = 0
        let gate = DispatchSemaphore(value: 0)
        let body = similarJSON
        StubURLProtocol.handler = { _ in _ = gate.wait(timeout: .now() + 2); return (200, body) }
        let toggle = Task { await c.toggleVibeMode(client: .stubbed()) }
        await waitUntil(message: "the fetch never started") { !StubURLProtocol.requests.isEmpty }
        c.queueOrigin = .songPath
        gate.signal()
        await waitUntil(message: "the replace question never opened") { c.vibeReplacePrompt != nil }
        return toggle
    }

    func testVibeButtonAsksBeforeReplacingAQueueTheMapStarted() async throws {
        let c = controller()
        let toggle = try await toggleOvertakenBySongPath(c)
        XCTAssertEqual(c.vibeReplacePrompt?.question, "replace the song path with similar tracks?")
        XCTAssertTrue(c.isVibeLoading)
        c.resolveVibeReplace(false)
        await toggle.value
        XCTAssertEqual(c.queueOrigin, .songPath)
        XCTAssertEqual(c.queue.map(\.id), ["a"])
        XCTAssertFalse(c.isVibeLoading)
        XCTAssertNil(c.vibeNotice)
    }

    func testVibeButtonReplacesWhenTheUserAgrees() async throws {
        let c = controller()
        let toggle = try await toggleOvertakenBySongPath(c)
        c.resolveVibeReplace(true)
        await toggle.value
        XCTAssertEqual(c.queueOrigin, .playSimilar)
        XCTAssertEqual(c.queue.map(\.id), ["a", "x"])
        XCTAssertEqual(c.vibeMatchScore, 100)
        XCTAssertFalse(c.isVibeLoading)
    }

    func testTheReplaceQuestionShowsOnTheNewestHost() {
        let c = controller()
        let shell = UUID(), player = UUID()
        c.addVibeReplaceHost(shell)
        c.addVibeReplaceHost(player)
        XCTAssertEqual(c.vibeReplaceHosts.last, player)
        c.removeVibeReplaceHost(player)
        XCTAssertEqual(c.vibeReplaceHosts.last, shell, "closing the cover hands the question back")
        c.addVibeReplaceHost(shell)
        XCTAssertEqual(c.vibeReplaceHosts, [shell], "a host that reappears is listed once")
    }

    // MARK: blend answers

    private func blendJSON(_ id: String) -> Data {
        Data(#"{"tracks":[{"id":"\#(id)","title":"t","duration":10,"album":{"id":"al","title":"x"},"artist":{"id":"ar","name":"n"}}]}"#.utf8)
    }

    private func picks() -> VibeBlendPicks {
        var p = VibeBlendPicks()
        p.add(VibeTrackPick(id: "m", title: "m", artist: "a"), to: .more)
        return p
    }

    func testBlendAnswerFromBeforeTheReopenIsDropped() async {
        StubURLProtocol.handler = { _ in (200, self.blendJSON("old")) }
        let vm = VibeMapViewModel()
        vm.panel = .blend
        let run = Task { await vm.runBlend(picks: self.picks(), client: .stubbed()) }
        await waitUntil(message: "the blend request never fired") { !StubURLProtocol.requests.isEmpty }
        vm.panel = nil
        vm.panel = .blend
        await run.value
        XCTAssertTrue(vm.blendResults.isEmpty)
        XCTAssertFalse(vm.isBlending)
    }

    func testBlendAnswerLandsWhenNothingChanged() async {
        StubURLProtocol.handler = { _ in (200, self.blendJSON("new")) }
        let vm = VibeMapViewModel()
        vm.panel = .blend
        await vm.runBlend(picks: picks(), client: .stubbed())
        XCTAssertEqual(vm.blendResults.map(\.id), ["new"])
    }

    func testSelectionChangeClearsTheOldPlayError() {
        let vm = VibeMapViewModel()
        vm.selectedTrackId = "a"
        vm.playError = "couldn't play"
        vm.selectedTrackId = "b"
        XCTAssertNil(vm.playError)
    }

    // MARK: library scan polling

    func testLeavingTheScreenStopsPolling() async throws {
        StubURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("/library/scan") == true { return (200, Data(#"{"jobId":"j"}"#.utf8)) }
            return (200, Data(#"{"status":"active","progress":10}"#.utf8))
        }
        let sync = LibrarySyncModel(pollInterval: .milliseconds(10))
        sync.start(client: .stubbed())
        await waitUntil(message: "scan polling never started") { StubURLProtocol.requests.count >= 4 }
        sync.cancel()
        try await Task.sleep(for: .milliseconds(100))
        let settled = StubURLProtocol.requests.count
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(StubURLProtocol.requests.count, settled)
        XCTAssertFalse(sync.isRunning)
    }

    func testScanPollingEndsWhenTheModelIsGone() async throws {
        StubURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("/library/scan") == true { return (200, Data(#"{"jobId":"j"}"#.utf8)) }
            return (200, Data(#"{"status":"active","progress":10}"#.utf8))
        }
        var sync: LibrarySyncModel? = LibrarySyncModel(pollInterval: .milliseconds(10))
        weak let weakSync = sync
        sync?.start(client: .stubbed())
        await waitUntil(message: "scan polling never started") { StubURLProtocol.requests.count >= 3 }
        sync = nil
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(weakSync)
    }
}
