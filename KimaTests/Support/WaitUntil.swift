import XCTest

extension XCTestCase {
    /// Poll `condition` every 10 ms until it turns true or `timeout` seconds pass. For loops that
    /// can't be awaited directly (keeper cycles, reconnect attempts). A wait that runs out fails
    /// the test at the caller's line, so a stalled precondition can't pass the asserts after it
    /// vacuously. A wait whose timeout is the point (a bound on something that must not happen)
    /// says so: `expectTimeout: true` fails instead when the condition turns true. `message` says
    /// what didn't happen, so the wait carries the assert's words and no assert restates it.
    /// Each tick checks the condition BEFORE the deadline, so a wait rounds up to the next poll:
    /// shrinking `timeout` at idle cannot force a red. A flake that appears only under load is
    /// reproduced by simulating starvation, not by hoping for it — every actor hop needs a
    /// main-actor turn, and the measured hog recipe (busy-wait the main actor beside the subject)
    /// sits at `stubRoundtripTimeout`, SSEManagerReconnectTests (ticket 21).
    @MainActor
    func waitUntil(
        _ timeout: TimeInterval = 2, message: String = "", expectTimeout: Bool = false,
        file: StaticString = #filePath, line: UInt = #line,
        _ condition: () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        var met = await condition()
        while !met, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
            met = await condition()
        }
        if met == expectTimeout {
            let why = expectTimeout ? "the condition turned true within \(timeout) s" : "timed out after \(timeout) s"
            XCTFail("waitUntil: \(why)" + (message.isEmpty ? "" : " — \(message)"), file: file, line: line)
        }
    }
}
