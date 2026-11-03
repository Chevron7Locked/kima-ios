import Foundation

// MARK: - Release Radar domain models
// GET /api/releases/radar → { upcoming, recent, monitoredArtistCount, similarArtistCount }.
// Decoding is defensive: id accepts Int or String and other fields default, so one bad row doesn't blank the list.

/// Where the release entry originated — Lidarr calendar (monitored) or Last.fm similar artists.
enum ReleaseSource: String, Codable, Sendable {
    case lidarr, similar
}

/// Current state of a release relative to today.
enum ReleaseStatus: String, Codable, Sendable {
    case upcoming, released, available
}

/// One entry in the Release Radar — an upcoming or recently-released album
/// from a monitored or related artist.
struct ReleaseItem: Identifiable, Sendable {
    let id: String          // normalised from Int or String on the wire
    let title: String
    let artistName: String
    let artistMbid: String?
    let albumMbid: String
    let releaseDate: String // ISO 8601 date string from Lidarr calendar
    let coverUrl: String?   // absolute Lidarr cover URL — use RemoteArtworkImage
    let source: ReleaseSource
    let status: ReleaseStatus
    let inLibrary: Bool
    let canDownload: Bool   // false when upcoming or already in library
}

extension ReleaseItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, title, artistName, artistMbid, albumMbid
        case releaseDate, coverUrl, source, status, inLibrary, canDownload
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id: normalise Int (Lidarr) or String to a plain String.
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        }
        title       = (try? c.decode(String.self, forKey: .title))       ?? "unknown title"
        artistName  = (try? c.decode(String.self, forKey: .artistName))  ?? "unknown artist"
        artistMbid  =  try? c.decode(String.self, forKey: .artistMbid)
        albumMbid   = (try? c.decode(String.self, forKey: .albumMbid))   ?? ""
        releaseDate = (try? c.decode(String.self, forKey: .releaseDate)) ?? ""
        coverUrl    =  try? c.decode(String.self, forKey: .coverUrl)
        source      = (try? c.decode(ReleaseSource.self, forKey: .source))  ?? .lidarr
        status      = (try? c.decode(ReleaseStatus.self, forKey: .status))  ?? .released
        inLibrary   = (try? c.decode(Bool.self, forKey: .inLibrary))    ?? false
        canDownload = (try? c.decode(Bool.self, forKey: .canDownload))  ?? false
    }
}

/// Top-level envelope for GET /api/releases/radar.
struct ReleasesRadarResponse: Decodable, Sendable {
    let upcoming: [ReleaseItem]
    let recent: [ReleaseItem]
    let monitoredArtistCount: Int
    let similarArtistCount: Int

    private enum CodingKeys: String, CodingKey {
        case upcoming, recent, monitoredArtistCount, similarArtistCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Element-by-element so one malformed/null entry drops just that entry, not the whole list.
        upcoming             = ((try? c.decode([FailableDecodable<ReleaseItem>].self, forKey: .upcoming)) ?? []).compactMap(\.value)
        recent               = ((try? c.decode([FailableDecodable<ReleaseItem>].self, forKey: .recent))   ?? []).compactMap(\.value)
        monitoredArtistCount = (try? c.decode(Int.self, forKey: .monitoredArtistCount)) ?? 0
        similarArtistCount   = (try? c.decode(Int.self, forKey: .similarArtistCount))   ?? 0
    }
}

/// Request body for POST /api/releases/download/:albumMbid — the mbid alone can't drive the
/// underlying source search, so the radar row's artist/title come along for the ride.
private struct ReleaseDownloadBody: Encodable, Sendable {
    let artistName: String
    let albumTitle: String
}

/// Response shape for POST /api/releases/download/:albumMbid.
struct ReleaseDownloadResponse: Decodable, Sendable {
    let success: Bool
    let jobId: String
    let message: String?
}

// MARK: - KimaAPIClient releases extension

extension KimaAPIClient {

    /// GET /api/releases/radar — upcoming + recent releases for monitored artists.
    func releasesRadar() async throws -> ReleasesRadarResponse {
        try await get("/releases/radar", authed: true)
    }

    /// POST /api/releases/download/:albumMbid — queue a release for download via Lidarr. `artistName` and `albumTitle`
    /// are required (the release-group mbid alone can't drive the source search). Returns the created job's id; no
    /// polling needed, since the job appears in the `/downloads` activity stack (`getActiveDownloads()`) under that id.
    func downloadRelease(albumMbid: String, artistName: String, albumTitle: String) async throws -> ReleaseDownloadResponse {
        let body = ReleaseDownloadBody(artistName: artistName, albumTitle: albumTitle)
        return try await postJSON("/releases/download/\(albumMbid)", body: body, authed: true)
    }
}
