import Foundation

// Radio metadata endpoints. Station batches come from getRadioPage in KimaAPIClient+Library.swift.

// MARK: - Private response envelopes

private struct GenresResponse: Codable, Sendable {
    let genres: [RadioGenre]
}

private struct DecadesResponse: Codable, Sendable {
    let decades: [RadioDecade]
}

private struct MoodStationsResponse: Decodable, Sendable {
    let stations: [MoodStationInfo]
}

private struct EnrichmentProgressResponse: Decodable, Sendable {
    struct Stage: Decodable, Sendable {
        let total: Int
        let completed: Int
        let progress: Int
    }
    let moods: Stage?
}

// MARK: - API methods

extension KimaAPIClient {

    /// GET /api/library/genres → `{ genres: [{ genre, count }] }` — raw counts, unfiltered. Callers apply the
    /// "count ≥ 15" filter and cache the result in RadioViewModel for the life of the view.
    func getGenres() async throws -> [RadioGenre] {
        let response: GenresResponse = try await get("/library/genres", authed: true)
        return response.genres
    }

    /// GET /api/library/decades → `{ decades: [{ decade, count }] }`
    ///
    /// Returns decade entries sorted by the server (typically descending). The Radio screen
    /// shows all returned decades; the Home section caps to the top 4.
    func getDecades() async throws -> [RadioDecade] {
        let response: DecadesResponse = try await get("/library/decades", authed: true)
        return response.decades
    }

    /// GET /api/library/radio/stations → `{ stations: [{ value, name, description }] }` — the server's
    /// mood stations in display order. Play one with `type=mood&value=<value>`.
    func getMoodStations() async throws -> [MoodStationInfo] {
        let response: MoodStationsResponse = try await get("/library/radio/stations", authed: true)
        return response.stations
    }

    /// GET /api/enrichment/progress, reduced to the mood step: the percent of the library's songs that have their mood
    /// scores, or nil once every song has them (or the server reports no mood step).
    func getMoodAnalysisPercent() async throws -> Int? {
        let response: EnrichmentProgressResponse = try await get("/enrichment/progress", authed: true)
        guard let moods = response.moods, moods.total > 0, moods.completed < moods.total else { return nil }
        return min(99, max(0, moods.progress))
    }
}
