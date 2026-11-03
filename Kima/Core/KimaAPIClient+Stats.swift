import Foundation

// MARK: - Stats domain
// The whole page is one request (gathers run concurrently server-side); drills are separate reads since most
// visits never ask them. `tz` is the device's IANA zone; without it the hour-of-day grid would be drawn in UTC.
// The admin `system` block is not consumed on iOS (single-user app).

extension KimaAPIClient {

    private static let tzKey = "tz"

    /// The device's IANA timezone, sent on every stats read that buckets by
    /// hour of day (grid, signature, hour drill).
    static var statsTimezone: String { TimeZone.current.identifier }

    /// GET /stats — the whole page in one gather: listening (windowed by
    /// `period`), shelf/spoken (all-time), and the audio-read signature.
    func getStats(period: StatsPeriod) async throws -> StatsResponse {
        try await get("/stats", query: [
            Self.tzKey: Self.statsTimezone,
            "period": period.rawValue,
        ], authed: true)
    }

    /// GET /stats read for its shelf block alone (how much of the library has been played), for the library
    /// masthead. The server has no smaller route for it; the shelf is all-time, and the 30-day window keeps the
    /// rest of the gather smallest.
    func getShelfStats() async throws -> ShelfStats {
        struct ShelfOnly: Decodable { let shelf: ShelfStats }
        let res: ShelfOnly = try await get("/stats", query: [
            Self.tzKey: Self.statsTimezone,
            "period": StatsPeriod.d30.rawValue,
        ], authed: true)
        return res.shelf
    }

    /// GET /stats/hour — what was playing in one cell of the week. The period
    /// must match the grid the cell was read from, or the cell says 109 and
    /// the panel lists twelve.
    func getHourDetail(weekday: Int, hour: Int, period: StatsPeriod) async throws -> HourDetail {
        try await get("/stats/hour", query: [
            "dow": String(weekday),
            "hour": String(hour),
            Self.tzKey: Self.statsTimezone,
            "period": period.rawValue,
        ], authed: true)
    }

    /// GET /stats/region — what sits at one point of the taste plot.
    func getRegionDetail(x: Int, y: Int, period: StatsPeriod) async throws -> RegionDetail {
        try await get("/stats/region", query: [
            "x": String(x),
            "y": String(y),
            "period": period.rawValue,
        ], authed: true)
    }

    /// GET /stats/tracks — a slice of the page as something you can play.
    /// `slice` is top|never|core|key|decade; key/decade narrow key/decade slices.
    func getPlayableSlice(of slice: String, key: String? = nil, decade: Int? = nil,
                          limit: Int? = nil, period: StatsPeriod) async throws -> [Track] {
        var query = ["of": slice, "period": period.rawValue]
        if let key { query["key"] = key }
        if let decade { query["decade"] = String(decade) }
        if let limit { query["limit"] = String(limit) }
        let res: PlayableSliceResponse = try await get("/stats/tracks", query: query, authed: true)
        return res.tracks
    }

    /// GET /stats/track/:id/plays — how many times this person has heard one
    /// track (its own tiny read; it changes as you listen).
    func getTrackPlayCount(trackId: String) async throws -> Int {
        let res: TrackPlaysResponse = try await get("/stats/track/\(trackId)/plays", authed: true)
        return res.plays
    }

    // MARK: - The play-history audit (false starts)

    /// GET /stats/false-starts — what the audit can prove, grouped by track.
    /// One pass over an entire history; can take tens of seconds.
    func getFalseStartAudit() async throws -> FalseStartAudit {
        try await get("/stats/false-starts", authed: true)
    }

    /// POST /stats/false-starts/collapse — merge duplicate rows written while
    /// the song was still playing. No track list; changes no play count.
    func collapseDuplicatePlayRows() async throws -> StatsCountsResponse {
        struct EmptyBody: Encodable {}
        return try await postJSON("/stats/false-starts/collapse", body: EmptyBody(), authed: true)
    }

    /// POST /stats/false-starts/remove — delete the provable ones on these
    /// tracks. Destructive; cap 2000 tracks per call (server-enforced).
    func removeFalseStarts(trackIds: [String]) async throws -> StatsCountsResponse {
        try await postJSON("/stats/false-starts/remove", body: TrackIdsBody(trackIds: trackIds), authed: true)
    }

    /// POST /stats/false-starts/ignore — stop raising these tracks. Deletes nothing.
    func ignoreFalseStartTracks(trackIds: [String]) async throws -> StatsCountsResponse {
        try await postJSON("/stats/false-starts/ignore", body: TrackIdsBody(trackIds: trackIds), authed: true)
    }

    /// POST /stats/false-starts/restore — put ignored tracks back in the audit.
    func unignoreFalseStartTracks(trackIds: [String]) async throws -> StatsCountsResponse {
        try await postJSON("/stats/false-starts/restore", body: TrackIdsBody(trackIds: trackIds), authed: true)
    }
}
