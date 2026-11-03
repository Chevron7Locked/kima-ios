import Foundation
import os

// MARK: - Vibe map logging

/// Shared logger for the vibe-map fetch contract (202 computing ↔ 200 ready).
let vibeMapLog = Logger(subsystem: "com.chevron7locked.kima", category: "vibe-map")

// MARK: - Request body types (private to this file)

private struct VibePathRequest: Encodable {
    let startTrackId: String
    let endTrackId: String
    let length: Int?
    let mode: String?
}

private struct VibeAlchemyRequest: Encodable {
    let add: [String]
    let subtract: [String]
    let limit: Int
}

private struct VibeSearchRequest: Encodable {
    let query: String
    let limit: Int
}

// MARK: - Lenient map envelope

/// Wire shape of `GET /vibe/map`: either the full projection (200) or the
/// "working on it" placeholder (202 `{computing:true}`). Keyed by `tracks` presence —
/// the 202 body has no track array, the 200 body always does.
enum VibeMapEnvelope: Decodable {
    case ready(VibeMapResponse)
    case computing

    private enum CodingKeys: String, CodingKey { case tracks, computing }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.tracks) {
            self = .ready(try VibeMapResponse(from: decoder))
        } else if (try? container.decode(Bool.self, forKey: .computing)) == true {
            self = .computing
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "vibe map response is neither a projection nor {computing:true}"
            ))
        }
    }
}

// MARK: - KimaAPIClient + Vibe Map

extension KimaAPIClient {

    // MARK: - Map

    /// GET /api/vibe/map — every track's stored place on the 3-D map (x, y, z, colour, moods, energy, valence).
    /// The server answers 202 `{computing:true}` while laying out: a body with tracks decodes to `.ready`, a bare
    /// `{computing:true}` to `.computing`. Callers poll; computing is never an error.
    func getVibeMap() async throws -> VibeMapOutcome {
        #if DEBUG
        if let status = DebugVibeComputingSimulator.failStatus {
            throw APIError.http(status: status, body: "debug: -kima-vibe-fail")
        }
        if await DebugVibeComputingSimulator.shouldSimulateComputing() {
            vibeMapLog.debug("vibe map: simulated computing answer (debug flag)")
            return .computing
        }
        #endif
        let envelope: VibeMapEnvelope = try await get("/vibe/map", authed: true)
        switch envelope {
        case .ready(let response): return .ready(response)
        case .computing:
            vibeMapLog.debug("vibe map: server answered computing (202)")
            return .computing
        }
    }

    // MARK: - Path

    /// POST /api/vibe/path — a journey between two tracks by interpolating CLAP embeddings. Throws
    /// `APIError.http(400, …)` when start == end or the tracks are too similar ("TRACKS_TOO_SIMILAR"); suggest
    /// "Similar Tracks" instead. `length` is clamped to 5–50 (omit for the server default); `mode` is "smooth"
    /// (default) or "discovery" (wider deviations).
    func vibePath(
        startTrackId: String,
        endTrackId: String,
        length: Int? = nil,
        mode: String? = nil
    ) async throws -> VibePathResponse {
        let body = VibePathRequest(
            startTrackId: startTrackId,
            endTrackId: endTrackId,
            length: length,
            mode: mode
        )
        return try await postJSON("/vibe/path", body: body, authed: true)
    }

    // MARK: - Alchemy

    /// POST /api/vibe/alchemy — vector arithmetic: mean(add) − mean(subtract), nearest tracks in embedding space.
    /// `add` takes 1–10 track IDs, `subtract` 0–10; all must have CLAP embeddings (else 400). `limit` clamped to 1–100 (default 20).
    func vibeAlchemy(
        add: [String],
        subtract: [String] = [],
        limit: Int = 20
    ) async throws -> VibeAlchemyResponse {
        let body = VibeAlchemyRequest(add: add, subtract: subtract, limit: limit)
        return try await postJSON("/vibe/alchemy", body: body, authed: true)
    }

    // MARK: - Search

    /// POST /api/vibe/search — natural-language vibe search (CLAP text embedding, nearest tracks).
    /// Server enforces a 2–500 character query (400 otherwise) and clamps `limit` to 1–100 (default 20).
    func vibeSearch(
        query: String,
        limit: Int = 20
    ) async throws -> VibeSearchResponse {
        let body = VibeSearchRequest(query: query, limit: limit)
        return try await postJSON("/vibe/search", body: body, authed: true)
    }

}
