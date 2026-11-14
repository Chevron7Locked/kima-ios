import XCTest

extension XCTestCase {
    /// Poll `condition` every 10 ms until it turns true or `timeout` seconds pass. For loops that
    /// can't be awaited directly (keeper cycles, reconnect attempts). Waiting alone proves nothing:
    /// always assert the fact after waiting — waitUntil only guarantees time passed.
    @MainActor
    func waitUntil(_ timeout: TimeInterval = 2, _ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
