import Foundation
import Observation
import os

/// Source of an artist: a numeric library ID means the artist is owned; a UUID means discovery.
enum ArtistSource: Equatable { case library, discovery }

/// View model for the artist detail screen. `load` tries the library endpoint, then discovery.
/// `playAll` / `shuffleAll` fetch every owned album's tracks in parallel and queue them by disc and track number.
/// `startRadio` is for library artists only; `preview` plays 30-second clips and pauses the main player.
/// `palette` loads after the artist resolves; the hero uses the amber glow until it is ready.
private let artistVMLogger = Logger(subsystem: "com.chevron7locked.kima", category: "ArtistDetailViewModel")

@MainActor
@Observable
final class ArtistDetailViewModel {

    // MARK: - Observable state

    var phase: LoadPhase<Artist> = .loading
    var albumSortOrder: AlbumSort = .year
    var palette: CoverArtPalette? = nil
    var isLoadingAction: Bool = false  // true while playAll / radio fetch is in flight

    /// 30-second clips for unowned popular tracks.
    let preview = ClipPreviewPlayer()

    // MARK: - Nested types

    enum AlbumSort: String, CaseIterable, Identifiable {
        case year     = "newest"
        case dateAdded = "recently added"
        var id: String { rawValue }
    }

    // MARK: - Source detection (mirrors web `useArtistData`)

    /// Numeric id → library; UUID containing "-" → discovery.
    static func source(for artist: Artist) -> ArtistSource {
        artist.id.contains("-") ? .discovery : .library
    }

    // MARK: - Load

    /// Load artist data, trying the library endpoint first then falling back to discovery.
    /// `name` is passed by callers that have the full artist so a backend 5xx can fall back to discovery by name;
    /// a numeric library id 404s on the discovery route. Navigation routes carry only the id, so it is optional.
    func load(id: String, name: String? = nil, using client: KimaAPIClient) async {
        let hadContent: Bool
        if case .loaded = phase { hadContent = true } else { hadContent = false; phase = .loading }
        do {
            phase = .loaded(try await client.getArtist(id: id))
            return
        } catch {
            if Task.isCancelled { return }
            if hadContent { return }
            recordLoadFailure(id: id, name: name, attempt: .library, error: error)

            // Transient backend enrichment failures (5xx) on a real library id: retry the
            // library endpoint once before falling back — the enrichment often succeeds on retry.
            if isServerError(error), let artist = try? await client.getArtist(id: id) {
                phase = .loaded(artist)
                return
            }

            guard shouldTryDiscovery(after: error, id: id) else {
                phase = .failed(error.localizedDescription)
                return
            }

            // Prefer discovery BY NAME (avoids the failing library-id enrichment path); fall
            // back to the id only when no name is available (near-guaranteed 404 for a numeric id,
            // but the true cause is already on the breadcrumb by then).
            let discoveryKey = (name?.isEmpty == false) ? name! : id
            do {
                phase = .loaded(try await client.getArtistDiscovery(nameOrMbid: discoveryKey))
            } catch let discoveryError {
                if Task.isCancelled { return }
                recordLoadFailure(id: id, name: name, attempt: .discovery, error: discoveryError)
                phase = .failed(discoveryError.localizedDescription)
            }
        }
    }

    /// Retry via discovery when the first failure is a genuine 404, a backend 5xx (discovery-by-name may still
    /// resolve), or the id is discovery-shaped (an mbid/UUID containing "-"). The true failure is recorded to the
    /// breadcrumb before this runs, so the fallback cannot mask a decode/5xx failure behind discovery's 404.
    private func shouldTryDiscovery(after error: Error, id: String) -> Bool {
        if case APIError.http(let status, _) = error {
            if status == 404 { return true }
            if isServerErrorStatus(status) { return true }
        }
        return id.contains("-")   // discovery-shaped id (mbid/uuid)
    }

    private func isServerError(_ error: Error) -> Bool {
        if case APIError.http(let status, _) = error { return isServerErrorStatus(status) }
        return false
    }

    private func isServerErrorStatus(_ status: Int) -> Bool { (500...599).contains(status) }

    /// Record a load failure to both the unified log and the durable, pull-able breadcrumb file
    /// (`artist-load-errors.json`) so the exact cause (HTTP status + body, or the `DecodingError`
    /// key path) can be confirmed off-device on the next install.
    private func recordLoadFailure(id: String, name: String?, attempt: ArtistLoadAttempt, error: Error) {
        if case APIError.decoding(let underlying) = error {
            artistVMLogger.error("Artist \(attempt.rawValue, privacy: .public) decode FAILED for \(id, privacy: .public): \(String(describing: underlying), privacy: .public)")
        } else {
            artistVMLogger.error("Artist \(attempt.rawValue, privacy: .public) FAILED for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        ArtistLoadDiagnostics.record(id: id, name: name, attempt: attempt, error: error)
    }

    /// Load the cover-art palette asynchronously.
    func loadPalette(artist: Artist, server: KimaServer) async {
        let coverId = artist.userHeroUrl ?? artist.coverArt ?? artist.image
        palette = await CoverArtColor.palette(coverId: coverId, server: server)
    }

    // MARK: - Album sorting

    func sortedAlbums(_ albums: [Album]) -> [Album] {
        switch albumSortOrder {
        case .year:
            return albums.sorted {
                ($0.displayYear ?? $0.year ?? 0) > ($1.displayYear ?? $1.year ?? 0)
            }
        case .dateAdded:
            return albums.sorted { ($0.lastSynced ?? "") > ($1.lastSynced ?? "") }
        }
    }

    /// Owned albums from the full artist album list (web: `albums.filter(a => a.owned)`).
    func ownedAlbums(from albums: [Album]) -> [Album] {
        albums.filter { $0.owned == true }
    }

    /// Available (unowned) albums — rendered as "Albums Available" / "Singles and EPs".
    func availableAlbums(from albums: [Album]) -> [Album] {
        albums.filter { $0.owned != true }
    }

    // MARK: - Play All / Shuffle All

    /// Start playback from the beginning of the artist's own music, newest album first. The queue
    /// and its order come from the server (see `startQueue`).
    func playAll(artist: Artist, client: KimaAPIClient, player: PlaybackController, toast: ToastCenter) async {
        await startQueue(artist: artist, client: client, player: player, toast: toast, shuffle: false)
    }

    /// Same as `playAll` but shuffles the combined track list before handing it to the player.
    func shuffleAll(artist: Artist, client: KimaAPIClient, player: PlaybackController, toast: ToastCenter) async {
        await startQueue(artist: artist, client: client, player: player, toast: toast, shuffle: true)
    }

    /// Play All / Shuffle All: the queue comes from `getArtistPlayTracks` — one request, ordered
    /// by the server, so a failed request fails the tap.
    private func startQueue(
        artist: Artist,
        client: KimaAPIClient,
        player: PlaybackController,
        toast: ToastCenter,
        shuffle: Bool
    ) async {
        guard artist.albums?.contains(where: { $0.owned == true }) == true else { return }
        isLoadingAction = true
        defer { isLoadingAction = false }

        do {
            let queue = try await client.getArtistPlayTracks(id: artist.id)
            guard !queue.tracks.isEmpty else {
                toast.show("\(artist.effectiveName.lowercased()) has no playable tracks", style: .error)
                return
            }
            player.play(tracks: shuffle ? queue.tracks.shuffled() : queue.tracks, startAt: 0, shuffle: false)
        } catch {
            toast.show("couldn't play \(artist.effectiveName.lowercased())", style: .error)
        }
    }

    // MARK: - Radio (library artists only)

    /// Start artist radio. Only call when `source(for:) == .library`.
    func startRadio(artist: Artist, client: KimaAPIClient, player: PlaybackController, toast: ToastCenter) async {
        isLoadingAction = true
        defer { isLoadingAction = false }
        do {
            let artistId = artist.id
            let tracks = try await client.getRadioTracks(type: "artist", value: artistId)
            guard !tracks.isEmpty else {
                toast.show("not enough music for this artist's radio yet", style: .error)
                return
            }
            // Plays in the server's order, whatever the listener's shuffle. Refills ask again; the session drops
            // songs it already queued.
            player.playStation(tracks, serverOrdered: false, inOrder: true) {
                try await client.getRadioTracks(type: "artist", value: artistId)
            }
        } catch {
            toast.show("couldn't start artist radio. try again.", style: .error)
        }
    }

    // MARK: - Preview playback

    /// Address of the 30-second clip for an unowned popular track: the server's
    /// `/api/artists/preview/{artist}/{title}/stream` proxy, which resolves a fresh Deezer URL per
    /// playback. The payload's `track.previewUrl` expires ~27 h after the server fetched it (then it
    /// answers 403), so it is only a fallback when no ticket is available.
    func previewURL(track: Track, artistName: String, server: KimaServer, client: KimaAPIClient) async -> URL? {
        let streamToken = await client.streamTicket()
        if let tok = streamToken {
            return PreviewURL.track(base: server, artistName: artistName, trackTitle: track.title, token: tok)
        }
        if let raw = track.previewUrl, !raw.isEmpty, let u = URL(string: raw) {
            return u
        }
        return nil
    }

    // MARK: - Downloads

    /// POST /api/downloads — queue all of an artist's albums via Lidarr.
    ///
    /// Server fans out into per-album jobs; response includes `albumCount`.
    /// Mirrors `useDownloadActions.downloadArtist` — shows "Preparing…" then success/error toast.
    func downloadArtist(_ artist: Artist, client: KimaAPIClient, toast: ToastCenter) async {
        guard let mbid = artist.mbid else {
            toast.show("can't download: this artist has no MusicBrainz ID", style: .error)
            return
        }
        toast.show("starting download: \(artist.name)…", style: .info)
        do {
            let response = try await client.downloadArtist(name: artist.name, mbid: mbid)
            let count = response.albumCount ?? 0
            if count > 0 {
                toast.show("downloading \(artist.name) (\(count) album\(count == 1 ? "" : "s"))", style: .success)
            } else {
                toast.show("downloading \(artist.name)", style: .success)
            }
        } catch {
            toast.show(AcquirePermission.failureMessage(error, fallback: "couldn't start the download. try again."),
                       style: .error)
        }
    }

    /// POST /api/downloads — queue a single unowned album via Lidarr.
    ///
    /// Called from `ArtistAvailableAlbumsSection` download buttons.
    /// Mirrors `useDownloadActions.downloadAlbum`.
    func downloadAlbum(_ album: Album, client: KimaAPIClient, toast: ToastCenter) async {
        // Artist name sourced from the artist in the current loaded phase
        let artistName: String
        if case .loaded(let artist) = phase {
            artistName = artist.name
        } else {
            artistName = album.artist?.name ?? ""
        }
        await AlbumDownloadAction.run(album: album, artistName: artistName, client: client, toast: toast)
    }
}
