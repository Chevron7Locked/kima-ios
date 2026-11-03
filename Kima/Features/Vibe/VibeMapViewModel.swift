import CoreGraphics
import Foundation
import Observation
import os

// MARK: - VibeMapViewModel

/// View-model for VibeMapView. Call `load(client:)` once from `.task`. Empty tracks (analysis not complete) are
/// surfaced as `.loaded([])` so the view shows a friendly note instead of an error.
@MainActor
@Observable
final class VibeMapViewModel {

    // MARK: - State

    var phase: LoadPhase<[VibeMapTrack]> = .loading

    /// Id of the currently-selected track point on the map. Set by the scene tap callback;
    /// cleared on empty-space tap or card dismiss.
    var selectedTrackId: String? = nil {
        didSet {
            guard selectedTrackId != oldValue else { return }
            playError = nil
            noteStep(.deselect, on: selectedTrackId != nil)
        }
    }

    /// True while `play(trackId:client:player:)` is resolving the full Track via the API.
    var isPlayLoading = false

    /// Non-nil when the last play resolution failed — shown in the readout.
    var playError: String? = nil

    // MARK: - Panels

    /// The song path or blend panel that is open. Closing one keeps its picks for the session, so
    /// reopening it shows them again; the blend's result (lit on the map) closes with it.
    var panel: VibePanel? = nil {
        didSet {
            if panel != .blend { blendResults = []; isBlending = false }
            if panel != oldValue {
                blendRequest += 1
                noteStep(.closePanel, on: panel != nil)
            }
        }
    }

    /// The song path's two ends (a star tap or a search pick fills them).
    var songPath = VibeSongPathForm()

    /// The blend's "more like" and "less like" picks (search, the readout or the rail adds to them).
    var blendPicks = VibeBlendPicks()

    /// Counts blend requests and panel changes; an answer from an older count is dropped.
    var blendRequest = 0

    /// The tracks the last blend found (lit on the map, listed in the panel).
    var blendResults: [VibeResultTrack] = []
    var isBlending = false

    // MARK: Search over the loaded map

    /// What is typed in the top search box.
    var searchQuery: String = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            searchListHidden = false
            noteStep(.clearSearch, on: !searchQuery.isEmpty)
        }
    }

    /// Matches for `searchQuery` over the loaded map (every match lights up).
    var searchMatches: VibeLibrarySearch.Matches = .none

    /// The result list collapses after a pick; typing opens it again.
    var searchListHidden = false

    /// Album id → name, looked up for search results that share a title.
    var albumTitles: [String: String] = [:]
    @ObservationIgnored var albumLookups: Set<String> = []

    /// The loaded tracks, folded once per map for instant matching.
    private(set) var libraryIndex: VibeLibraryIndex = .empty
    @ObservationIgnored var indexTask: Task<Void, Never>?

    /// Bumps to fly the camera to `flyToId`.
    var flyTrigger = 0
    var flyToId: String?

    /// Non-nil when a panel action fails; shown inside the panel and cleared on the next attempt.
    var modeError: String? = nil

    // MARK: - Map identity, colour, legend, overlays

    /// Identifies one layout: `computedAt|trackCount|moodSignature`. Nil until a map is applied.
    private(set) var mapKey: String?

    /// Bumps each time a different map is applied; the renderer rebuilds its buffers on a change.
    private(set) var mapGeneration = 0

    /// Track id → place on the logo gradient. Empty when the server sends no colour.
    private(set) var colourById: [String: Double] = [:]

    /// One chip per dominant mood in the loaded map.
    var legendEntries: [VibeLegendEntry] = []

    /// Dominant mood key → ids of the tracks with that mood.
    var tracksByMood: [String: [String]] = [:]

    /// The legend chip that is pinned, if any.
    var legendPinned: String? { didSet { if legendPinned != oldValue { noteStep(.unpinMood, on: legendPinned != nil) } } }

    /// Ids found by "show similar" (the track itself first).
    var similarIds: [String] = [] { didSet { if similarIds != oldValue { noteStep(.clearSimilar, on: !similarIds.isEmpty) } } }

    /// What the back button can undo, oldest first: each kind moves to the end when it turns on and
    /// leaves when it turns off.
    private(set) var stepOrder: [VibeStepBack] = []

    private func noteStep(_ step: VibeStepBack, on: Bool) {
        stepOrder.removeAll { $0 == step }
        if on { stepOrder.append(step) }
    }

    /// Track the queue was built from (play similar, or where a song path starts).
    var operationSourceId: String?

    /// One-shot message for a toast; the view clears it after showing.
    var notice: String?

    /// Colour (0 azure … 1 amber) of a track, or nil when the server sent none for it.
    func colour(for trackId: String) -> Double? { colourById[trackId] }

    // MARK: - Top moods

    /// Top 3 mood keys across the loaded tracks, most common first. Built once in `apply` so
    /// `HomeHeroView` does not regroup 20k tracks on every body pass.
    var topMoods: [String] = []

    /// Each song's, album's and artist's main mood and the library's mood shares, for the library screen.
    private(set) var libraryMoods: LibraryMoods = .empty

    // MARK: - Queue-starting work

    /// Running map actions, keyed so closing the map can cancel them all. The work itself
    /// (`launch` / `cancelOperations` / `play`) lives in VibeMapViewModel+Playback.swift.
    @ObservationIgnored var operationTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Data loading
    //
    // load / backgroundRevalidate / stopPolling / startPolling and the poll constants live in
    // VibeMapViewModel+Polling.swift; the poll task and the computing flag stay here (Swift allows no
    // stored properties in extensions).

    /// True while the server answers 202 `{computing:true}` (the map is being laid out).
    /// Drives the "mapping your library…" copy over the plain loading spinner.
    var isComputing = false

    @ObservationIgnored var pollTask: Task<Void, Never>?

    /// Single write-site for a freshly decoded projection. The same map twice changes nothing.
    func apply(_ response: VibeMapResponse) {
        let key = "\(response.computedAt)|\(response.trackCount)|\(response.moodSignature ?? "-")"
        if key == mapKey, case .loaded = phase { return }
        mapKey = key
        mapGeneration += 1
        colourById = Dictionary(
            response.tracks.compactMap { t in t.colour.map { (t.id, $0) } },
            uniquingKeysWith: { first, _ in first })
        buildLegend(from: response.tracks)
        if legendPinned.map({ tracksByMood[$0] == nil }) == true { legendPinned = nil }
        rebuildLibraryIndex(from: response.tracks)
        phase = .loaded(response.tracks)
        topMoods = Self.computeTopMoods(from: response.tracks)
        libraryMoods = LibraryMoods(tracks: response.tracks)
    }

    /// Folds the track names off the main actor (tens of milliseconds for a big library). The previous
    /// index answers searches meanwhile; the open query runs again when the new one lands.
    /// Stays in the class: `libraryIndex` has a private setter, which an extension file cannot use.
    private func rebuildLibraryIndex(from tracks: [VibeMapTrack]) {
        let generation = mapGeneration
        indexTask?.cancel()
        indexTask = Task { [weak self] in
            let index = await Task.detached(priority: .userInitiated) { VibeLibraryIndex(tracks: tracks) }.value
            guard let self, !Task.isCancelled, self.mapGeneration == generation else { return }
            self.libraryIndex = index
            self.updateSearch()
        }
    }

}
