import XCTest

extension XCTestCase {
    /// Poll `condition` every 10 ms until it turns true or `timeout` seconds pass. For loops that
    /// can't be awaited directly (keeper cycles, reconnect attempts). Waiting alone proves nothing:
    /// always assert the fact after waiting — waitUntil only guarantees time passed. Each tick
    /// checks the condition BEFORE the deadline, so a wait rounds up to the next poll: shrinking
    /// `timeout` at idle cannot force a red. A flake that appears only under load is reproduced by
    /// simulating starvation, not by hoping for it — every actor hop needs a main-actor turn, and
    /// the measured hog recipe (busy-wait the main actor beside the subject) sits at
    /// `stubRoundtripTimeout`, SSEManagerReconnectTests (ticket 21).
    @MainActor
    func waitUntil(_ timeout: TimeInterval = 2, _ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
