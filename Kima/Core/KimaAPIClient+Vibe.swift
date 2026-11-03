import Foundation

// MARK: - Vibe API response envelopes

/// Response shape for GET /api/system/features — which server-side analyzers are running.
/// `vibeEmbeddings: true` means the library has CLAP embeddings and vibe mode is available.
struct SystemFeatures: Codable, Sendable {
    let vibeEmbeddings: Bool
}

private struct VibeSimilarResponse: Codable, Sendable {
    let sourceTrackId: String
    let tracks: [VibeResultTrack]
}

// MARK: - KimaAPIClient vibe extension

extension KimaAPIClient {

    // MARK: - System features (availability gate)

    /// GET /api/system/features.
    /// Fetch once per session to determine whether vibe mode is available.
    func getSystemFeatures() async throws -> SystemFeatures {
        try await get("/system/features", authed: true)
    }

    // MARK: - Vibe similarity

    /// GET /api/vibe/similar/:trackId?limit=N — tracks like this one, with each one's `similarity`
    /// (0–1), the source for the vibe match-score badge. A track that hasn't been analysed, or has no similar tracks,
    /// answers 404. `audioFeatures` is nil on the returned tracks (the endpoint does not send them).
    func getVibeSimilarTracksWithSimilarity(
        trackId: String,
        limit: Int = 50
    ) async throws -> (tracks: [Track], similarities: [String: Double]) {
        let safe = KimaServer.pathSegment(trackId)
        let response: VibeSimilarResponse = try await get(
            "/vibe/similar/\(safe)",
            query: ["limit": "\(limit)"],
            authed: true
        )
        var similarities: [String: Double] = [:]
        let tracks = response.tracks.map { vt -> Track in
            if let similarity = vt.similarity {
                similarities[vt.id] = similarity
            }
            return vt.asTrack()
        }
        return (tracks, similarities)
    }
}
