import Foundation

// MARK: - PlaylistAddSource → [Track] resolver
// Single source of truth for resolving a library source (tracks / album / artist) to an ordered [Track] list,
// used by the Add-to-Playlist sheet (maps to IDs) and every Add-to-Queue surface.

/// Tracks resolved from a library source, and how many of its albums failed to load
/// (callers say "couldn't load n albums" rather than silently playing fewer songs).
struct ResolvedTracks: Sendable {
    var tracks: [Track]
    var failedAlbums = 0
}

extension KimaAPIClient {

    /// Resolve a `PlaylistAddSource` to an ordered list of `Track` objects. Returns `nil` when the album or artist
    /// itself can't be fetched, and an empty list when the source has no owned tracks.
    func resolveTracks(for source: PlaylistAddSource) async -> ResolvedTracks? {
        switch source {
        case .tracks(let tracks):
            return ResolvedTracks(tracks: tracks)
        case .album(let id):
            guard let album = try? await getAlbum(id: id) else { return nil }
            return ResolvedTracks(tracks: album.tracksInOrder)
        case .artist(let id):
            guard let artist = try? await getArtist(id: id) else { return nil }
            return await ownedTracks(of: artist)
        }
    }

    // MARK: - Artist path (newest-album-first, concurrent album fetch)

    /// All owned tracks of an artist — newest album first, then disc/track order within each
    /// album — counting the albums whose detail failed to load. Fetches album details
    /// concurrently in chunks of 8 to bound in-flight requests.
    func ownedTracks(of artist: Artist) async -> ResolvedTracks {
        let owned = (artist.albums ?? [])
            .filter { $0.owned == true }
            .sorted { ($0.displayYear ?? $0.year ?? 0) > ($1.displayYear ?? $1.year ?? 0) }
        guard !owned.isEmpty else { return ResolvedTracks(tracks: []) }

        // Cap concurrent album-detail fetches at 8 (a prolific artist can have 100+ albums).
        // Chunking keeps the order trivial: each chunk collects indexed pairs independently,
        // and the final sort by idx still produces the correct album sequence.
        let concurrencyLimit = 8
        let enumerated = Array(owned.enumerated())
        var indexed: [(idx: Int, tracks: [Track]?)] = []
        indexed.reserveCapacity(owned.count)

        var chunkStart = 0
        while chunkStart < enumerated.count {
            let chunkEnd = min(chunkStart + concurrencyLimit, enumerated.count)
            let chunk = enumerated[chunkStart..<chunkEnd]
            await withTaskGroup(of: (idx: Int, tracks: [Track]?).self) { group in
                for (idx, stub) in chunk {
                    let albumId = stub.id
                    group.addTask {
                        guard let detail = try? await self.getAlbum(id: albumId) else { return (idx, nil) }
                        return (idx, detail.tracksInOrder)
                    }
                }
                for await pair in group { indexed.append(pair) }
            }
            chunkStart = chunkEnd
        }

        let ordered = indexed.sorted { $0.idx < $1.idx }
        return ResolvedTracks(tracks: ordered.flatMap { $0.tracks ?? [] },
                              failedAlbums: ordered.filter { $0.tracks == nil }.count)
    }
}
