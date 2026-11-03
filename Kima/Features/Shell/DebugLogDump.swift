#if DEBUG
import Foundation
import OSLog

/// DEBUG-only (`-kima-log-dump`): copies this app's own log messages into Documents/kima-log.txt every few
/// seconds, so a test run on a phone can be read back over Wi-Fi with `devicectl device copy from`.
enum DebugLogDump {
    static func run() async {
        guard CommandLine.arguments.contains("-kima-log-dump"),
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        let file = docs.appendingPathComponent("kima-log.txt")
        try? Data().write(to: file)
        var since = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { continue }
            let entries = (try? store.getEntries(at: store.position(date: since)))?
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == "com.chevron7locked.kima" && $0.date > since } ?? []
            guard let last = entries.last else { continue }
            since = last.date
            let text = entries.map { "\($0.date.formatted(.iso8601.time(includingFractionalSeconds: true))) [\($0.category)] \($0.composedMessage)" }
                .joined(separator: "\n") + "\n"
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(Data(text.utf8))
                try? handle.close()
            }
        }
    }
}
#endif
