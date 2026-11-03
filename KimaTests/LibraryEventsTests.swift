import XCTest
@testable import Kima

@MainActor
final class LibraryEventsTests: XCTestCase {
    func testEventBurstBecomesOneLibraryRefresh() async throws {
        let sse = SSEManager()
        sse.libraryRefreshSpacing = .milliseconds(100)
        for _ in 0..<5 { sse.handle(data: #"{"type":"enrichment:progress","phase":"vibe"}"#) }
        sse.handle(data: #"{"type":"scan:complete","jobId":"7","result":{}}"#)
        XCTAssertEqual(sse.libraryTick, 0)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(sse.libraryTick, 1)
        XCTAssertEqual(sse.lastScan, SSEManager.ScanEvent(jobId: "7", progress: 100, finished: true, failed: false))

        sse.handle(data: #"{"type":"scan:complete","jobId":"8"}"#)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(sse.libraryTick, 2)
    }

    func testScanProgressUpdatesTheSyncRowWithoutRefreshingTheLibrary() async throws {
        let sse = SSEManager()
        sse.libraryRefreshSpacing = .milliseconds(50)
        sse.handle(data: #"{"type":"scan:progress","jobId":"7","progress":40}"#)
        XCTAssertEqual(sse.lastScan?.progress, 40)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(sse.libraryTick, 0)

        let sync = LibrarySyncModel()
        sync.apply(try XCTUnwrap(sse.lastScan))
        XCTAssertEqual(sync.state, .scanning(40))
        sync.apply(SSEManager.ScanEvent(jobId: "7", progress: 100, finished: true, failed: false))
        XCTAssertEqual(sync.state, .done)
    }
}
