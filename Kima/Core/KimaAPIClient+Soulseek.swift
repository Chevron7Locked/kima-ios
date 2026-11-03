import Foundation

// MARK: - Soulseek (P2P) models
// GET /api/soulseek/status is the feature gate (enabled/connected/username). POST /search starts an async P2P
// search and returns a searchId; GET /search/:id polls accumulated results. POST /download blocks up to ~120s.

/// One P2P search hit, as the server's search results send it.
///
/// `id` is a computed, stable identity — the server assigns no id of its own — built from
/// `username + "/" + path`, which uniquely identifies a single peer's file.
struct SoulseekResult: Decodable, Identifiable, Sendable {
    let username:     String
    let path:         String
    let filename:     String
    let size:         Int
    let bitrate:      Int
    /// e.g. "flac" / "mp3" — see `formatSearchResult`'s extension sniff.
    let format:       String
    let parsedArtist: String?
    let parsedAlbum:  String?
    let parsedTitle:  String?

    var id: String { "\(username)/\(path)" }
}

/// GET /api/soulseek/status response. `enabled == false` when the server has no Soulseek
/// credentials configured — callers gate the whole feature (search scope, filter chip) on this.
struct SoulseekStatus: Decodable, Sendable {
    let enabled:   Bool
    let connected: Bool
    let username:  String?
}

// MARK: - Request bodies / response envelopes (private)

private struct SoulseekSearchBody: Encodable, Sendable {
    let query: String
}

private struct SoulseekSearchStartResponse: Decodable, Sendable {
    let searchId: String
    let message:  String?
}

private struct SoulseekSearchResultsResponse: Decodable, Sendable {
    let results: [SoulseekResult]
    let count:   Int?
}

/// POST /soulseek/download body. Optional fields are omitted from the JSON payload when nil
/// (Swift's synthesized `Encodable` uses `encodeIfPresent` for `Optional`-typed stored
/// properties) — the server derives artist/title/album from the filename when absent, so
/// omission (not `null`) is the correct wire shape either way.
private struct SoulseekDownloadBody: Encodable, Sendable {
    let username: String
    let filepath: String
    let filename: String?
    let size:     Int?
    let artist:   String?
    let album:    String?
    let title:    String?
}

/// POST /soulseek/download response. Success shape `{success, filePath, message}`; failure
/// shape `{success:false, error}` arrives as a non-2xx and is never decoded here — see
/// `downloadFromSoulseek`, which discards the body entirely.
private struct SoulseekDownloadResponse: Decodable, Sendable {
    let success:  Bool?
    let filePath: String?
    let message:  String?
}

// MARK: - KimaAPIClient + Soulseek

extension KimaAPIClient {

    /// GET /api/soulseek/status — feature gate. Callers should treat any failure as
    /// "not available" (best-effort; ignore errors, leave the scope hidden).
    func getSoulseekStatus() async throws -> SoulseekStatus {
        try await get("/soulseek/status", authed: true)
    }

    /// POST /api/soulseek/search — starts a P2P search on the server and returns its `searchId`;
    /// poll `getSoulseekSearchResults(searchId:)` for the results as they arrive.
    func searchSoulseek(query: String) async throws -> String {
        let resp: SoulseekSearchStartResponse = try await postJSON(
            "/soulseek/search",
            body: SoulseekSearchBody(query: query),
            authed: true
        )
        return resp.searchId
    }

    /// GET /api/soulseek/search/:searchId — accumulated results for a running or finished search. A 404 (unknown or
    /// expired searchId) is thrown, not swallowed into `[]`, so the poll loop in `SearchViewModel.performSoulseekSearch`
    /// can tell it from "zero results so far" and stop without wiping the last-known-good results.
    func getSoulseekSearchResults(searchId: String) async throws -> [SoulseekResult] {
        let resp: SoulseekSearchResultsResponse = try await get(
            "/soulseek/search/\(searchId)",
            authed: true
        )
        return resp.results
    }

    /// POST /api/soulseek/download — starts the real P2P transfer; the server blocks up to ~120s, so this goes over
    /// the long-timeout session (`postJSONLongTimeout`). The response body is discarded: progress surfaces through the
    /// Downloads/Activity feed (a `DownloadJob` is created server-side and ticks `env.events.downloadTick`).
    func downloadFromSoulseek(
        username: String,
        filepath: String,
        filename: String?,
        size:     Int?,
        artist:   String?,
        album:    String?,
        title:    String?
    ) async throws {
        let body = SoulseekDownloadBody(
            username: username,
            filepath: filepath,
            filename: filename,
            size:     size,
            artist:   artist,
            album:    album,
            title:    title
        )
        let _: SoulseekDownloadResponse = try await postJSONLongTimeout(
            "/soulseek/download",
            body: body,
            authed: true
        )
    }
}
