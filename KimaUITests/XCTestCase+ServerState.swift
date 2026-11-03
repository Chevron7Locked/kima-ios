import XCTest

extension XCTestCase {
    /// Runs the app's DEBUG server-state hook in a launch of its own: `action` is "snapshot" or "restore", `keys` a
    /// comma-separated list (DebugServerState). Returns the result line: "saved: …", "restored: …", or "problem: …"
    /// naming what failed or still differs.
    @discardableResult
    func serverState(_ action: String, _ keys: String) -> String {
        let app = XCUIApplication()
        app.launchArguments = ["-kima-\(action)", keys]
        app.launch()
        let result = app.staticTexts["kima-state-result"]
        let line = result.waitForExistence(timeout: 90) ? result.label : "problem: the app showed no result"
        XCTContext.runActivity(named: "server state \(action): \(line)") { _ in }
        app.terminate()
        return line
    }

    /// The number after `key ` in a snapshot line, e.g. 10000 from "saved: queue-limit 10000; …".
    func snapshotNumber(_ line: String, _ key: String) -> Int? {
        let part = line.components(separatedBy: "; ").first { $0.contains("\(key) ") }
        return part?.components(separatedBy: "\(key) ").last.flatMap { Int($0.prefix { $0.isNumber }) }
    }
}
