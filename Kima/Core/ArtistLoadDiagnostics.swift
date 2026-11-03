import Foundation

/// Which endpoint attempt produced the failure being recorded.
enum ArtistLoadAttempt: String, Codable, Sendable {
    /// `GET /library/artists/:id` — the primary library lookup.
    case library
    /// `GET /artists/discover/:nameOrMbid` — the discovery fallback.
    case discovery
}

/// One recorded artist-detail load failure, written to a pull-able JSON file so the real cause (HTTP status and
/// body slice, or the `DecodingError` path) can be read off-device; the error state shows the user no detail.
/// Carries only an error slice and decoder key paths, never tokens, auth headers or full payloads.
struct ArtistLoadError: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    /// Device local clock at the moment of failure.
    var capturedAt: Date = Date()
    /// The artist id that was being loaded (numeric library id, name, or mbid).
    var artistId: String
    /// The artist name, when the caller had it (recommended cards do; navigation routes don't).
    var artistName: String?
    /// Which endpoint attempt failed.
    var attempt: ArtistLoadAttempt
    /// Coarse bucket: `http`, `decoding`, `network`, `unauthorized`, or `other`.
    var failureKind: String
    /// HTTP status, when `failureKind == "http"`.
    var httpStatus: Int?
    /// Truncated response body slice, when the server returned one.
    var bodySnippet: String?
    /// `String(describing:)` of the underlying `DecodingError` — the exact CodingKey path +
    /// expected type — when `failureKind == "decoding"`.
    var decodingDetail: String?
    /// Short human-readable summary.
    var message: String
}

/// Durable, pull-able breadcrumb for artist-detail load failures. Uses `IssueReportStore`'s on-disk contract
/// (a JSON array under `<Documents>`, pulled with `devicectl device copy from --domain-type appDataContainer`),
/// but is a write-only static logger callable from any context, not an `@Observable` store.
enum ArtistLoadDiagnostics {
    /// `<Documents>/artist-load-errors.json`.
    static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("artist-load-errors.json")
    }

    /// Keep only the most recent N entries so the file can't grow unbounded.
    private static let maxEntries = 50
    private static let maxSnippet = 800

    /// Serializes all file access so sequential library→discovery failures can't corrupt the array.
    private static let queue = DispatchQueue(label: "com.chevron7locked.kima.artist-load-diagnostics")

    /// Classify an `Error` (typically `APIError`) into a structured entry and append it. Fire-and-forget.
    static func record(id: String, name: String?, attempt: ArtistLoadAttempt, error: Error) {
        var entry = ArtistLoadError(
            artistId: id,
            artistName: name,
            attempt: attempt,
            failureKind: "other",
            message: ""
        )

        switch error {
        case APIError.http(let status, let body):
            entry.failureKind = "http"
            entry.httpStatus = status
            entry.bodySnippet = body.map(truncate)
            entry.message = "HTTP \(status)"
        case APIError.decoding(let underlying):
            entry.failureKind = "decoding"
            entry.decodingDetail = truncate(String(describing: underlying))
            entry.message = "decode failed"
        case APIError.network(let underlying):
            entry.failureKind = "network"
            entry.message = truncate(underlying.localizedDescription)
        case APIError.unauthorized:
            entry.failureKind = "unauthorized"
            entry.message = "unauthorized"
        default:
            entry.failureKind = "other"
            entry.message = truncate(String(describing: error))
        }

        append(entry)
    }

    // MARK: - Disk I/O (off the caller's thread)

    private static func append(_ entry: ArtistLoadError) {
        queue.async {
            var entries: [ArtistLoadError] = []
            if let data = try? Data(contentsOf: fileURL),
               let existing = try? DiagnosticsFileCodec.decoder.decode([ArtistLoadError].self, from: data) {
                entries = existing
            }
            entries.append(entry)
            if entries.count > maxEntries {
                entries = Array(entries.suffix(maxEntries))
            }
            if let data = try? DiagnosticsFileCodec.encoder.encode(entries) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    private static func truncate(_ s: String) -> String {
        s.count <= maxSnippet ? s : String(s.prefix(maxSnippet)) + "…(truncated)"
    }
}
