import Foundation
import Observation

@MainActor
@Observable
final class AlbumDetailViewModel {

    var phase: LoadPhase<Album> = .loading {
        didSet { rebuildTrackCache() }
    }

    // MARK: - Precomputed track caches
    //
    // `AlbumTrackListView` reads `combinedTracks`, `discSections` and the owned play queue on every body re-render.
    // Rebuilding them in `phase.didSet` pays the cost once per load, not once per frame.

    /// @ObservationIgnored — the cache is invalidated via `phase.didSet`; the parent view's
    /// observation of `phase` already triggers a body refresh on load, so AlbumTrackListView
    /// will re-read these values immediately after they are updated.
    @ObservationIgnored private(set) var cachedSections: [DiscSection] = []
    @ObservationIgnored private(set) var cachedOwnedQueue: [Track] = []

    private func rebuildTrackCache() {
        guard case .loaded(let album) = phase else {
            cachedSections = []
            cachedOwnedQueue = []
            return
        }
        let combined = Self.combinedTracks(album: album)
        cachedSections = Self.discSections(from: combined)
        cachedOwnedQueue = album.tracksInOrder
    }

    /// Clip player for missing/unowned tracks (separate from the main queue).
    let preview = ClipPreviewPlayer()

    // MARK: - Load (with discovery fallback)

    func load(id: String, using client: KimaAPIClient) async {
        let hadContent: Bool
        if case .loaded = phase { hadContent = true } else { hadContent = false; phase = .loading }
        do {
            let album = try await client.getAlbum(id: id)
            phase = .loaded(album)
        } catch {
            if Task.isCancelled { return }
            if hadContent { return }
            // Not in the library: fall back to the discovery album by release-group id.
            do {
                let album = try await client.getAlbumDiscovery(rgMbid: id)
                phase = .loaded(album)
            } catch let fallbackError {
                if Task.isCancelled { return }
                phase = .failed(fallbackError.localizedDescription)
            }
        }
    }

    // MARK: - Ownership

    static func isOwned(_ album: Album) -> Bool { album.owned ?? false }

    // MARK: - Pull-to-refresh

    /// Same fetch path as `load` (library → discovery fallback) but WITHOUT resetting `phase`
    /// to `.loading` first, so a pull keeps the current album on screen and swaps in place.
    /// Throws so the view can surface failure via ToastCenter; on throw `phase` is untouched.
    func refresh(id: String, using client: KimaAPIClient) async throws {
        do {
            let album = try await client.getAlbum(id: id)
            phase = .loaded(album)
        } catch {
            // Same discovery fallback as load.
            let album = try await client.getAlbumDiscovery(rgMbid: id)
            phase = .loaded(album)
        }
    }

    // MARK: - Combined track list

    /// Merges owned tracks and missing tracks interleaved by disc/track number.
    /// Numbered missing tracks are merged in-order with owned; unnumbered appended at end.
    /// Missing tracks are returned as synthetic Track values (`isMissing = true`, `duration = 0`).
    static func combinedTracks(album: Album) -> [Track] {
        let owned = album.tracksInOrder

        let allMissing = (album.missingTracks ?? [])
            .enumerated()
            .map { i, m -> Track in
                Track(
                    id: "missing-\(m.trackNumber.map(String.init) ?? "x")-\(i)-\(m.title)",
                    title: m.title,
                    duration: 0,
                    trackNo: m.trackNumber,
                    trackNumber: m.trackNumber,
                    isMissing: true,
                    previewUrl: m.previewUrl
                )
            }

        let numbered = allMissing
            .filter { ($0.trackNumber ?? $0.trackNo) != nil }
            .sorted(by: Track.albumOrder)
        let unnumbered = allMissing.filter { ($0.trackNumber ?? $0.trackNo) == nil }

        // Merge-sort: for each owned track, flush any numbered missing tracks that sort before it
        var merged: [Track] = []
        var mi = 0
        for t in owned {
            while mi < numbered.count, Track.albumOrder(numbered[mi], t) {
                merged.append(numbered[mi])
                mi += 1
            }
            merged.append(t)
        }
        while mi < numbered.count { merged.append(numbered[mi]); mi += 1 }
        return merged + unnumbered
    }

    // MARK: - Disc grouping (operates on the combined track list, already sorted)

    struct DiscSection: Identifiable {
        let id: Int            // 1-based disc number
        let subtitle: String?  // from discSubtitle of the first track that carries one
        let tracks: [Track]
    }

    static func discSections(from tracks: [Track]) -> [DiscSection] {
        var byDisc: [Int: [Track]] = [:]
        for t in tracks { byDisc[t.discNumber ?? 1, default: []].append(t) }
        return byDisc.keys.sorted().compactMap { disc in
            guard let dt = byDisc[disc] else { return nil }
            return DiscSection(
                id: disc,
                subtitle: dt.first(where: { $0.discSubtitle != nil })?.discSubtitle,
                tracks: dt  // already in merge-sort order from combinedTracks
            )
        }
    }

    // MARK: - Add to Playlist

    /// Present the app-wide Add-to-Playlist picker for this album's already-loaded owned tracks,
    /// avoiding a refetch (the detail response includes `tracks`). The picker POSTs each track to
    /// the chosen (or newly-created) playlist.
    func addToPlaylist(_ album: Album, using picker: PlaylistPickerModel) {
        picker.present(.tracks(album.tracksInOrder))
    }

    // MARK: - Download

    /// POST /api/downloads — queue a Lidarr acquisition for an unowned album.
    ///
    /// Requires the album to have a release-group MBID (rgMbid) or mbid.
    /// On success/duplicate: shows an "Added to queue" toast (mirrors useDownloadActions).
    func downloadAlbum(_ album: Album, client: KimaAPIClient, toast: ToastCenter) async {
        await AlbumDownloadAction.run(album: album, artistName: album.artist?.name ?? "", client: client, toast: toast)
    }
}
