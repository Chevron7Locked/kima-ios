import Foundation
import Observation
import os.log

/// The home rails' play path: which card was tapped, what the server returned, what failed.
/// "I tapped it and nothing happened" is the bug class this exists to answer.
let homePlayLog = Logger(subsystem: "com.chevron7locked.kima", category: "home-play")

/// View model for the Home tab. Each rail has an independent `LoadPhase`, so requests complete and render in
/// parallel. `isLoading` (the full-screen spinner) stays true until all five non-browse phases resolve.
/// `isBrowseLoading` is independent: Featured Playlists shows its own skeleton without blocking the page.
@MainActor
@Observable
final class HomeViewModel {

    // MARK: - Rail phases

    var recentlyListenedPhase: LoadPhase<[RecentlyListenedItem]> = .loading
    var recentlyAddedPhase:    LoadPhase<[Artist]>               = .loading
    var mixesPhase:            LoadPhase<[HomeMix]>              = .loading
    var recommendedPhase:      LoadPhase<[Artist]>               = .loading
    var popularArtistsPhase:   LoadPhase<[HomePopularArtist]>    = .loading

    /// Featured playlists from GET /api/browse/all. Stored flat (not in a LoadPhase)
    /// because isBrowseLoading drives the skeleton; an empty array = no error state shown.
    var featuredPlaylists: [HomePlaylistPreview] = []

    // MARK: - Loading flags

    /// True while GET /api/browse/all is in flight. Featured Playlists shows its own
    /// skeleton internally rather than contributing to the full-screen gate.
    var isBrowseLoading = true

    /// True while POST /mixes/refresh is pending. Disables the refresh button.
    var isRefreshingMixes = false

    /// First error captured during the most recent `loadAll` run.
    /// Set by the primary rail loaders; reset to nil at the start of each `loadAll`.
    private(set) var loadError: Error? = nil

    /// True once a full `loadAll` has finished without being cancelled. Later visits refresh in place.
    private(set) var hasLoadedOnce = false

    // MARK: - Library totals (hero subline)

    var libraryArtistTotal: Int?
    var libraryAlbumTotal:  Int?

    // MARK: - Computed gate

    /// Full-screen loading gate — true until all five non-browse phases resolve.
    var isLoading: Bool {
        phaseLoading(recentlyListenedPhase) ||
        phaseLoading(recentlyAddedPhase)    ||
        phaseLoading(mixesPhase)            ||
        phaseLoading(recommendedPhase)      ||
        phaseLoading(popularArtistsPhase)
    }

    /// True when a load error was captured AND no primary-rail data came through.
    /// Used by HomeView to swap the empty feed for a "can't reach server" state
    /// rather than silently showing a blank page.
    var isServerUnreachable: Bool {
        guard loadError != nil else { return false }
        return recentlyListened.isEmpty &&
               recentlyAdded.isEmpty    &&
               mixes.isEmpty            &&
               recommended.isEmpty      &&
               popularArtists.isEmpty
    }

    // MARK: - Convenience accessors (nil-safe unwrap from LoadPhase)

    var recentlyListened: [RecentlyListenedItem] {
        if case .loaded(let v) = recentlyListenedPhase { return v }; return []
    }
    var recentlyAdded: [Artist] {
        if case .loaded(let v) = recentlyAddedPhase { return v }; return []
    }
    var mixes: [HomeMix] {
        if case .loaded(let v) = mixesPhase { return v }; return []
    }
    var recommended: [Artist] {
        if case .loaded(let v) = recommendedPhase { return v }; return []
    }
    var popularArtists: [HomePopularArtist] {
        if case .loaded(let v) = popularArtistsPhase { return v }; return []
    }

    // MARK: - Load

    /// Kick off all home data concurrently; each phase updates as its request completes. Call on first appear
    /// and on pull-to-refresh. On a refresh (`isRefresh`) the `.loaded` phases stay in place, so `isLoading`
    /// stays false: swapping `mainFeed` for the loading state would tear down the ScrollView and snap it to the
    /// top. Only the system `.refreshable` spinner shows; each rail swaps its data in place.
    func loadAll(using client: KimaAPIClient, isRefresh: Bool = false) async {
        if !isRefresh {
            recentlyListenedPhase = .loading
            recentlyAddedPhase    = .loading
            mixesPhase            = .loading
            recommendedPhase      = .loading
            popularArtistsPhase   = .loading
            featuredPlaylists     = []
            isBrowseLoading       = true
            libraryArtistTotal    = nil
            libraryAlbumTotal     = nil
        }
        loadError = nil

        async let a: Void = loadRecentlyListened(client, isRefresh: isRefresh)
        async let b: Void = loadRecentlyAdded(client, isRefresh: isRefresh)
        async let c: Void = loadMixes(client, isRefresh: isRefresh)
        async let d: Void = loadRecommended(client, isRefresh: isRefresh)
        async let e: Void = loadPopularArtists(client, isRefresh: isRefresh)
        async let f: Void = loadFeaturedPlaylists(client, isRefresh: isRefresh)
        async let g: Void = loadLibraryTotals(client)
        _ = await (a, b, c, d, e, f, g)
        if !Task.isCancelled { hasLoadedOnce = true }
    }

    // MARK: - Mixes actions

    /// Silently re-fetches the mixes rail — after the mood mixer saves a mix, or after the
    /// what's-new panel clears the saved mood mix. On error the existing rail stays.
    func reloadMixes(using client: KimaAPIClient) async {
        do { mixesPhase = .loaded(try await client.getMixes()) }
        catch { /* keep existing data on transient errors */ }
    }

    /// The home card whose play request is in flight: its badge spins and repeat taps are
    /// ignored. Mix ids and continue-listening ids share the set (they are disjoint), so a
    /// tapping user sees which card they already started.
    var startingIds: Set<String> = []

    /// Tapping a mix card: HomeMix carries metadata only, so fetch the mix's tracks via
    /// GET /mixes/:id, then play from the top. (The web opens a mix page; iOS plays directly.)
    func playMix(
        _ mix: HomeMix,
        using client: KimaAPIClient,
        player: PlaybackController,
        toast: ToastCenter
    ) async {
        guard !startingIds.contains(mix.id) else {
            homePlayLog.notice("mix tap ignored (already in flight): \(mix.id)")
            return
        }
        startingIds.insert(mix.id)
        defer { startingIds.remove(mix.id) }
        #if DEBUG
        await DebugCardPlayDelay.apply()
        #endif
        homePlayLog.notice("mix play tapped: \(mix.id) \"\(mix.name)\"")
        do {
            let tracks = try await client.getMixTracks(id: mix.id)
            guard !tracks.isEmpty else {
                homePlayLog.notice("mix returned no tracks: \(mix.id)")
                toast.show("this mix has no playable tracks", style: .error)
                return
            }
            homePlayLog.notice("mix tracks \(tracks.count), starting playback")
            player.play(tracks: tracks, startAt: 0)
            // `play` only commits the queue — the stream URL is minted afterwards, and the mini
            // player is not allowed on screen until a track is loaded. Releasing the card's busy
            // state at this point would leave the tap with no feedback at all, so hold it here.
            await waitUntilPlaybackResolves(player: player, label: "mix \(mix.id)")
        } catch {
            homePlayLog.error("mix fetch failed \(mix.id): \(error.localizedDescription)")
            toast.show("couldn't play \(mix.name.lowercased())", style: .error)
        }
    }

    /// Hold a card's busy state until the player is live or has failed, polling every 120 ms,
    /// bounded at 20 s so a stream that never mints cannot spin forever. Leaving is the caller's
    /// `defer` job — this only decides *when* the caller gets there.
    private func waitUntilPlaybackResolves(player: PlaybackController, label: String) async {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if player.isActive {
                homePlayLog.notice("playback live: \(label)")
                return
            }
            if case .error = player.engineStatus {
                homePlayLog.error("playback errored while waiting: \(label)")
                return
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        homePlayLog.error("playback unresolved after 20s: \(label) status=\(String(describing: player.engineStatus))")
    }

    /// Tapping a continue-listening card. The item's type picks what must be fetched (an
    /// audiobook, a podcast episode, a track), so this takes seconds; the card spins through
    /// it. A false result is the play path's own failure, so it shows the play-failure toast.
    func playRecent(
        _ item: RecentlyListenedItem,
        using client: KimaAPIClient,
        player: PlaybackController,
        toast: ToastCenter
    ) async {
        guard !startingIds.contains(item.id) else {
            homePlayLog.notice("continue tap ignored (already in flight): \(item.id)")
            return
        }
        startingIds.insert(item.id)
        defer { startingIds.remove(item.id) }
        #if DEBUG
        await DebugCardPlayDelay.apply()
        #endif
        homePlayLog.notice("continue play tapped: \(item.id) \"\(item.displayTitle)\"")
        if await !player.playRecent(item, client: client) {
            toast.show("couldn't play \(item.displayTitle.lowercased())", style: .error)
            return
        }
        await waitUntilPlaybackResolves(player: player, label: "continue \(item.id)")
    }

    /// POST /mixes/refresh — the section's refresh button. Swaps the rail on success.
    func refreshMixes(using client: KimaAPIClient, toast: ToastCenter) async {
        guard !isRefreshingMixes else { return }
        isRefreshingMixes = true
        defer { isRefreshingMixes = false }
        do {
            mixesPhase = .loaded(try await client.refreshMixes())
            toast.show("mixes refreshed", style: .success)
        } catch {
            toast.show("couldn't refresh mixes", style: .error)
        }
    }

    // MARK: - Private loaders

    private func loadRecentlyListened(_ client: KimaAPIClient, isRefresh: Bool) async {
        do { recentlyListenedPhase = .loaded(try await client.getRecentlyListened(limit: 10)) }
        catch {
            if Task.isCancelled { return }
            // On a refresh, keep the existing rail rather than blanking it to [].
            if !isRefresh { recentlyListenedPhase = .loaded([]) }
            if loadError == nil { loadError = error }
        }
    }

    private func loadRecentlyAdded(_ client: KimaAPIClient, isRefresh: Bool) async {
        do { recentlyAddedPhase = .loaded(try await client.getRecentlyAdded(limit: 10)) }
        catch {
            if Task.isCancelled { return }
            if !isRefresh { recentlyAddedPhase = .loaded([]) }
            if loadError == nil { loadError = error }
        }
    }

    private func loadMixes(_ client: KimaAPIClient, isRefresh: Bool) async {
        do { mixesPhase = .loaded(try await client.getMixes()) }
        catch {
            if Task.isCancelled { return }
            if !isRefresh { mixesPhase = .loaded([]) }
            if loadError == nil { loadError = error }
        }
    }

    private func loadRecommended(_ client: KimaAPIClient, isRefresh: Bool) async {
        do { recommendedPhase = .loaded(try await client.getRecommendations(limit: 10)) }
        catch {
            if Task.isCancelled { return }
            if !isRefresh { recommendedPhase = .loaded([]) }
            if loadError == nil { loadError = error }
        }
    }

    private func loadPopularArtists(_ client: KimaAPIClient, isRefresh: Bool) async {
        do { popularArtistsPhase = .loaded(try await client.getPopularArtists(limit: 20)) }
        catch {
            if Task.isCancelled { return }
            if !isRefresh { popularArtistsPhase = .loaded([]) }
            if loadError == nil { loadError = error }
        }
    }

    private func loadFeaturedPlaylists(_ client: KimaAPIClient, isRefresh: Bool) async {
        defer { isBrowseLoading = false }
        do { featuredPlaylists = try await client.getFeaturedPlaylists() }
        catch {
            if Task.isCancelled { return }
            if !isRefresh { featuredPlaylists = [] }
        }
    }

    private func loadLibraryTotals(_ client: KimaAPIClient) async {
        async let artists: Int? = try? await client.libraryCount(of: .artists)
        async let albums:  Int? = try? await client.libraryCount(of: .albums)
        // Only overwrite on a successful count so a failed (refresh) fetch keeps the
        // last known totals rather than blanking the hero subline.
        if let artists = await artists { libraryArtistTotal = artists }
        if let albums  = await albums  { libraryAlbumTotal  = albums }
    }

    private func phaseLoading<T>(_ phase: LoadPhase<T>) -> Bool {
        if case .loading = phase { return true }
        return false
    }
}
