#if DEBUG
import SwiftUI

/// DEBUG: saves the account state a UI test changes on a real server, then restores and re-reads it
/// (`-kima-snapshot <keys>`, later `-kima-restore <keys>`). Keys: queue, queue-limit (the server-wide max queue
/// length), scrobble-token (only whether one is set; a set token is never touched), podcast-progress (first podcast).
/// Snapshots live in Documents/kima-state; the result line names any difference.
enum DebugServerState {
    static let keys = ["queue", "queue-limit", "scrobble-token", "podcast-progress"]

    static var folder: URL {
        URL.documentsDirectory.appending(path: "kima-state", directoryHint: .isDirectory)
    }

    /// Runs the requested snapshot or restore and returns its result line, or nil when no hook was asked for.
    static func run(client: KimaAPIClient) async -> String? {
        if let list = DebugDeepLink.launchArgValue("-kima-snapshot") {
            return await each(list, verb: "saved") { try await snapshot($0, client: client) }
        }
        if let list = DebugDeepLink.launchArgValue("-kima-restore") {
            return await each(list, verb: "restored") { try await restore($0, client: client) }
        }
        return nil
    }

    private static func each(_ list: String, verb: String, _ work: (String) async throws -> String) async -> String {
        var parts: [String] = []
        for key in list.split(separator: ",").map(String.init) {
            guard keys.contains(key) else { parts.append("\(key) unknown"); continue }
            do { parts.append(try await work(key)) } catch { parts.append("\(key) failed: \(error)") }
        }
        let failed = parts.contains { $0.contains("failed") || $0.contains("differs") || $0.contains("unknown") }
        return "\(failed ? "problem" : verb): " + parts.joined(separator: "; ")
    }

    // MARK: Snapshot

    private static func snapshot(_ key: String, client: KimaAPIClient) async throws -> String {
        let state = try await read(key, client: client)
        try write(state, to: "\(key).json")
        return "\(key) \(summary(key, state))"
    }

    /// The state behind one key, reduced to what the restore puts back (never a secret).
    private static func read(_ key: String, client: KimaAPIClient) async throws -> DebugJSON {
        switch key {
        case "queue":
            return try await client.get("/playback-state", authed: true)
        case "queue-limit":
            let row: DebugJSON = try await client.get("/system-settings", authed: true)
            return .object(["maxQueueLength": row["maxQueueLength"] ?? .null])
        case "scrobble-token":
            let row: DebugJSON = try await client.get("/settings", authed: true)
            return .object(["hasListenbrainzToken": row["hasListenbrainzToken"] ?? .null])
        default:
            return try await readPodcastProgress(client: client)
        }
    }

    private static func summary(_ key: String, _ state: DebugJSON) -> String {
        switch key {
        case "queue":
            if state == .null { return "none" }
            return "\(state["queue"]?.array?.count ?? 0) songs at \(Int(state["currentIndex"]?.number ?? 0))"
        case "queue-limit": return "\(Int(state["maxQueueLength"]?.number ?? -1))"
        case "scrobble-token": return state["hasListenbrainzToken"]?.bool == true ? "token set" : "no token"
        default:
            let eps = state["episodes"]?.array ?? []
            return "\(eps.count) episodes, \(eps.filter { $0["progress"] != .null }.count) with a place"
        }
    }

    // MARK: Restore

    private static func restore(_ key: String, client: KimaAPIClient) async throws -> String {
        let before = try load("\(key).json")
        var now = try await read(key, client: client)
        var note = ""
        if comparable(key, now) != comparable(key, before) {
            note = try await putBack(key, before: before, now: now, client: client)
            now = try await read(key, client: client)
        }
        try write(now, to: "\(key).after.json")
        let same = comparable(key, now) == comparable(key, before)
        return "\(key) \(same ? "ok" : "differs")\(note.isEmpty ? "" : " (\(note))")"
    }

    /// The state with the fields a restore cannot set (server timestamps) left out.
    private static func comparable(_ key: String, _ state: DebugJSON) -> DebugJSON {
        switch key {
        case "queue": return state.removing("updatedAt")
        case "podcast-progress":
            let eps = (state["episodes"]?.array ?? []).map { ep in
                DebugJSON.object(["id": ep["id"] ?? .null, "progress": (ep["progress"] ?? .null).removing("lastPlayedAt")])
            }
            return .object(["podcastId": state["podcastId"] ?? .null, "episodes": .array(eps)])
        default: return state
        }
    }

    private static func putBack(_ key: String, before: DebugJSON, now: DebugJSON,
                                client: KimaAPIClient) async throws -> String {
        switch key {
        case "queue":
            guard before != .null else { return "the account had no saved queue; the server cannot remove one" }
            var body: [String: DebugJSON] = [:]
            for field in ["playbackType", "trackId", "audiobookId", "podcastId", "currentIndex", "isShuffle"] {
                body[field] = before[field] ?? .null
            }
            body["queue"] = before["queue"] == .null ? .array([]) : before["queue"]
            let _: DebugJSON = try await client.postJSON("/playback-state", body: DebugJSON.object(body), authed: true)
            return "put back"
        case "queue-limit":
            let _: DebugJSON = try await client.postJSON("/system-settings", body: before, authed: true)
            return "set back to \(Int(before["maxQueueLength"]?.number ?? -1))"
        case "scrobble-token":
            guard before["hasListenbrainzToken"]?.bool == false else { return "a token was set; not touched" }
            let clear = DebugJSON.object(["listenbrainzToken": .null])
            let _: DebugJSON = try await client.postJSON("/settings", body: clear, authed: true)
            return "token removed"
        default:
            return try await putBackPodcastProgress(before: before, now: now, client: client)
        }
    }

    // MARK: Podcast progress

    /// The first subscribed podcast (the one `-kima-open podcast` opens) and every episode's place, newest and
    /// oldest 200 so either sort is covered.
    private static func readPodcastProgress(client: KimaAPIClient) async throws -> DebugJSON {
        let list: DebugJSON = try await client.get("/podcasts", authed: true)
        guard let id = list.array?.first?["id"]?.string else { return .object(["podcastId": .null, "episodes": .array([])]) }
        var byId: [String: DebugJSON] = [:]
        var order: [String] = []
        for sort in ["newest", "oldest"] {
            var query = ["limit": "200", "offset": "0"]
            if sort == "oldest" { query["order"] = "oldest" }
            let page: DebugJSON = try await client.get("/podcasts/\(id)/episodes", query: query, authed: true)
            for ep in page["episodes"]?.array ?? [] {
                guard let epId = ep["id"]?.string, byId[epId] == nil else { continue }
                byId[epId] = .object(["id": .string(epId), "duration": ep["duration"] ?? .null,
                                      "progress": ep["progress"] ?? .null])
                order.append(epId)
            }
            if Int(page["total"]?.number ?? 0) <= 200 { break }
        }
        return .object(["podcastId": .string(id), "episodes": .array(order.compactMap { byId[$0] })])
    }

    /// Removes places the test added and puts back changed ones. A put-back place gets a new last-played
    /// time (the server sets it), so those episodes are counted in the note.
    private static func putBackPodcastProgress(before: DebugJSON, now: DebugJSON,
                                               client: KimaAPIClient) async throws -> String {
        guard let podcastId = before["podcastId"]?.string,
              podcastId == now["podcastId"]?.string else { return "the first podcast changed; nothing put back" }
        let current = Dictionary((now["episodes"]?.array ?? []).compactMap { ep in ep["id"]?.string.map { ($0, ep) } },
                                 uniquingKeysWith: { a, _ in a })
        var removed = 0, reset = 0
        for ep in before["episodes"]?.array ?? [] {
            guard let id = ep["id"]?.string, let nowEp = current[id] else { continue }
            let was = ep["progress"] ?? .null, isNow = nowEp["progress"] ?? .null
            guard was.removing("lastPlayedAt") != isNow.removing("lastPlayedAt") else { continue }
            let path = "/podcasts/\(podcastId)/episodes/\(id)/progress"
            if was == .null {
                try await client.deleteChecked(path, authed: true)
                removed += 1
            } else {
                let time = was["currentTime"]?.number ?? 0, pct = was["progress"]?.number ?? 0
                let duration = pct > 0 ? time * 100 / pct : (ep["duration"]?.number ?? 0)
                let body = DebugJSON.object(["currentTime": .number(time), "duration": .number(duration),
                                             "isFinished": was["isFinished"] ?? .bool(false)])
                let _: DebugJSON = try await client.postJSON(path, body: body, authed: true)
                reset += 1
            }
        }
        return "\(removed) places removed, \(reset) put back with a new last-played time"
    }

    // MARK: Files

    private static func write(_ state: DebugJSON, to name: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: folder.appending(path: name))
    }

    private static func load(_ name: String) throws -> DebugJSON {
        try JSONDecoder().decode(DebugJSON.self, from: Data(contentsOf: folder.appending(path: name)))
    }
}

/// Shows the hook's result line (identifier `kima-state-result`) once it has run.
struct DebugServerStateRunner: ViewModifier {
    let client: KimaAPIClient
    @State private var result: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let result {
                    Text(result)
                        .font(.system(size: 10))
                        .foregroundStyle(KimaColor.textPrimary)
                        .padding(KimaSpacing.xs)
                        .background(KimaColor.surface)
                        .accessibilityIdentifier("kima-state-result")
                }
            }
            .task { result = await DebugServerState.run(client: client) }
    }
}
#endif
