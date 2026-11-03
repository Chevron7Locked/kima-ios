import Foundation
import Observation

/// Radio stations, one instance on `AppEnvironment` shared by Home's radio rail (which applies its
/// own caps) and the Radio screen (full lists). Genres need at least 15 tracks to become a station.
/// Play flow: set loadingStationID, fetch GET /api/library/radio, error toast if
/// empty or below minTracks, else shuffle client-side, play, success toast; loadingStationID cleared in defer.
@MainActor
@Observable
final class RadioViewModel {

    // MARK: - State

    var genresPhase: LoadPhase<[RadioStation]> = .loading
    var decadesPhase: LoadPhase<[RadioStation]> = .loading
    /// The server's mood stations, in its order.
    var moodsPhase: LoadPhase<[RadioStation]> = .loading
    /// How far the server's mood analysis has got, while it is still running; nil when it is done or unknown.
    var moodAnalysisPercent: Int?
    /// Per mood station value: the covers and artists of some of its songs, for the station's tile. Loaded when a
    /// tile first shows, and again after each refresh; a tile keeps its old preview until the new one arrives.
    var previews: [String: LoadPhase<StationPreview>] = [:]
    /// Goes up with each refresh. Tiles key their preview load on it, so tiles already on screen load again.
    private(set) var previewGeneration = 0
    /// Per mood station value: the refresh its preview was last asked in.
    @ObservationIgnored private var previewAskedIn: [String: Int] = [:]
    /// ID of the station currently loading tracks. Nil when idle.
    var loadingStationID: String? = nil

    // MARK: - Load

    /// True after the first load — Home and the Radio screen both call `loadIfNeeded`, and only
    /// the first call fetches. Pull-to-refresh and the retry buttons fetch regardless.
    @ObservationIgnored private var loadStarted = false

    func loadIfNeeded(using client: KimaAPIClient) async {
        guard !loadStarted else { return }
        loadStarted = true
        await refresh(using: client)
    }

    /// Fetches mood stations, genres and decades together. Lists already shown stay up until the new ones
    /// arrive, and stay if the fetch fails. Returns false when any fetch failed.
    @discardableResult
    func refresh(using client: KimaAPIClient) async -> Bool {
        loadStarted = true
        previewGeneration += 1   // the tiles ask again, so they follow the library
        async let m = loadMoods(using: client)
        async let g = loadGenres(using: client)
        async let d = loadDecades(using: client)
        let (moodsOK, genresOK, decadesOK) = await (m, g, d)
        return moodsOK && genresOK && decadesOK
    }

    func retryMoods(using client: KimaAPIClient) async {
        moodsPhase = .loading
        await loadMoods(using: client)
    }

    /// Some of a mood station's songs, for its tile's covers and artists. Asked without a seed: the server keeps a
    /// listening session per seeded station (a few per listener), so a seeded preview would push out the listener's
    /// real one. Asked once per station per refresh; a failed or cancelled ask is asked again the next time the tile
    /// shows. A preview already shown stays until the new one arrives, and stays if the new ask fails.
    func loadPreview(_ station: RadioStation, using client: KimaAPIClient) async {
        guard let value = station.filterValue else { return }
        let generation = previewGeneration
        if previewAskedIn[value] == generation {
            if case .failed? = previews[value] {} else { return }
        }
        previewAskedIn[value] = generation
        let shown = previews[value]?.isLoaded == true
        if !shown { previews[value] = .loading }
        do {
            let page = try await client.getRadioPage(
                type: station.filterType, value: value, limit: 40, tz: TimeZone.current.identifier)
            guard previewAskedIn[value] == generation else { return }   // a newer refresh asked again
            previews[value] = .loaded(StationPreview(tracks: page.tracks))
        } catch {
            guard previewAskedIn[value] == generation else { return }
            // A tile that scrolled away cancels its ask: forget it, so the next tile to show asks again.
            if Task.isCancelled || error is CancellationError {
                previewAskedIn[value] = nil
                if !shown { previews[value] = nil }
            } else if !shown {
                previews[value] = .failed(error.localizedDescription)
            }
        }
    }

    func retryGenres(using client: KimaAPIClient) async {
        genresPhase = .loading
        await loadGenres(using: client)
    }

    func retryDecades(using client: KimaAPIClient) async {
        decadesPhase = .loading
        await loadDecades(using: client)
    }

    // MARK: - Private loaders

    @discardableResult
    private func loadMoods(using client: KimaAPIClient) async -> Bool {
        async let progress: Void = refreshMoodProgress(using: client)
        let ok: Bool
        do {
            moodsPhase = .loaded(RadioStationData.buildMoodStations(from: try await client.getMoodStations()))
            ok = true
        } catch {
            if !moodsPhase.isLoaded { moodsPhase = .failed(error.localizedDescription) }
            ok = false
        }
        await progress
        return ok
    }

    /// Asks how far the mood analysis has got. A server without the readout (404) or with one the app can't read shows
    /// no progress line; a dropped connection keeps the last answer.
    func refreshMoodProgress(using client: KimaAPIClient) async {
        do {
            moodAnalysisPercent = try await client.getMoodAnalysisPercent()
        } catch APIError.http(status: 404, _), APIError.decoding {
            moodAnalysisPercent = nil
        } catch {}
    }

    @discardableResult
    private func loadGenres(using client: KimaAPIClient) async -> Bool {
        do {
            let genres = try await client.getGenres().filter { $0.count >= 15 }
            genresPhase = .loaded(RadioStationData.buildGenreStations(from: genres))
            return true
        } catch {
            if !genresPhase.isLoaded { genresPhase = .failed(error.localizedDescription) }
            return false
        }
    }

    @discardableResult
    private func loadDecades(using client: KimaAPIClient) async -> Bool {
        do {
            decadesPhase = .loaded(RadioStationData.buildDecadeStations(from: try await client.getDecades()))
            return true
        } catch {
            if !decadesPhase.isLoaded { decadesPhase = .failed(error.localizedDescription) }
            return false
        }
    }

    // MARK: - What this server can play

    /// The quick-start stations this server can play: workout needs the sound analysis.
    func quickStations(moodsAvailable: Bool) -> [RadioStation] {
        RadioStationData.playable(RadioStationData.staticStations, moodsAvailable: moodsAvailable)
    }

    // MARK: - Play

    /// Start a radio station: fetch its first batch, validate, play, and keep it refilling as it plays. Stations the
    /// server orders (they answer with `next`) play in that order; the rest are shuffled here, batch by batch.
    /// Guard against concurrent play requests — only one station loads at a time.
    func play(
        station: RadioStation,
        using client: KimaAPIClient,
        player: PlaybackController,
        toast: ToastCenter
    ) async {
        guard loadingStationID == nil else { return }
        loadingStationID = station.id
        defer { loadingStationID = nil }

        do {
            let batches = StationBatches(client: client, type: station.filterType, value: station.filterValue)
            let first = try await batches.next()
            let fetched = first.tracks

            if fetched.isEmpty {
                toast.show("no tracks found for \(station.name)", style: .error)
                return
            }
            if fetched.count < station.minTracks {
                toast.show(
                    "not enough tracks for \(station.name) (\(fetched.count) found, need \(station.minTracks))",
                    style: .error
                )
                return
            }

            let serverOrdered = first.next != nil
            let tracks = serverOrdered ? fetched : fetched.shuffled()
            player.playStation(tracks, serverOrdered: serverOrdered) {
                let batch = try await batches.next().tracks
                return serverOrdered ? batch : batch.shuffled()
            }
            toast.show("playing \(station.name) radio (\(tracks.count) \(tracks.count == 1 ? "track" : "tracks"))", style: .success)

        } catch {
            toast.show("couldn't start the station", style: .error)
        }
    }
}
