import Foundation

// MARK: - Legend entry

/// One chip in the mood legend.
struct VibeLegendEntry: Equatable, Identifiable {
    let key: String
    let label: String
    let count: Int
    var id: String { key }
}

// MARK: - VibeMapViewModel + map state

extension VibeMapViewModel {

    // MARK: Legend

    /// Builds `legendEntries` and `tracksByMood` from a freshly applied map.
    /// The five moods come first, then the rest; each group by count, ties in first-seen order.
    /// Any key that is not a mood or "unanalyzed" (e.g. the "acoustic"/"electronic" sound axes)
    /// joins "neutral", so the legend shows one "no single mood" chip.
    func buildLegend(from tracks: [VibeMapTrack]) {
        var order: [String] = []
        var grouped: [String: [String]] = [:]
        for t in tracks {
            let m = t.dominantMood
            let key = VibeMoodPalette.isMood(m) || m == "unanalyzed" ? m : "neutral"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(t.id)
        }
        tracksByMood = grouped
        // `sorted` is not stable, so the first-seen position is part of the comparison.
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let sorted = order.sorted { a, b in
            let ma = VibeMoodPalette.isMood(a), mb = VibeMoodPalette.isMood(b)
            if ma != mb { return ma }
            let ca = grouped[a]?.count ?? 0, cb = grouped[b]?.count ?? 0
            if ca != cb { return ca > cb }
            return position[a, default: 0] < position[b, default: 0]
        }
        legendEntries = sorted.map {
            VibeLegendEntry(key: $0, label: VibeMoodPalette.label(for: $0), count: grouped[$0]?.count ?? 0)
        }
    }

    /// Pin or unpin a legend chip. Anything else going on is cleared first.
    func toggleLegend(_ key: String) {
        if hasActiveOverlay { clearAll() }
        legendPinned = (legendPinned == key) ? nil : key
    }

    /// True when a panel, search or similar result is active.
    var hasActiveOverlay: Bool {
        panel != nil || !searchQuery.isEmpty || !similarIds.isEmpty
    }

    /// Back to the plain map: no panel, search, similar result, pin or selection.
    /// `operationSourceId` stays: it describes the queue, not the map.
    func clearAll() {
        panel = nil
        modeError = nil
        clearSearch()
        similarIds = []
        legendPinned = nil
        selectedTrackId = nil
    }

    // MARK: Highlights

    /// The stars the renderer lights up.
    var highlightedIds: [String] {
        VibeHighlights.ids(.init(
            searchIds: searchMatches.ids, blendIds: blendResults.map(\.id), similarIds: similarIds,
            pinnedIds: legendPinned.flatMap { tracksByMood[$0] } ?? []))
    }

    // MARK: Operation ring

    /// What the ring on the queue's first star stands for: show similar wins, then what built the queue.
    func operationKind(queueOrigin: QueueOrigin?) -> VibeOperationKind {
        if !similarIds.isEmpty { return .similar }
        switch queueOrigin {
        case .playSimilar: return .playSimilar
        case .blend: return .blend
        case .songPath, nil: return .songPath
        }
    }

    // MARK: Errors

    /// Errors show in the open panel, otherwise as a one-shot toast.
    func report(_ message: String) {
        if panel != nil { modeError = message } else { notice = message }
    }

    // MARK: Search

    /// Recomputes matches for the current query. Typing a search drops a pinned mood.
    func updateSearch() {
        searchMatches = VibeLibrarySearch.search(libraryIndex, query: searchQuery)
        if searchMatches.count > 0 { legendPinned = nil }
    }

    func clearSearch() {
        searchQuery = ""
        searchMatches = .none
    }

    /// Once typing settles, looks up the album names that tell colliding search results apart, each
    /// album once per session; a failed lookup is tried again with the next results.
    func nameSharedTitleAlbums(client: KimaAPIClient, settle: Duration = .milliseconds(300)) async {
        try? await Task.sleep(for: settle)
        guard !Task.isCancelled else { return }
        let wanted = VibeLibrarySearch.albumsToName(searchMatches.top).filter { !albumLookups.contains($0.key) }
        albumLookups.formUnion(wanted.keys)
        for (albumId, trackId) in wanted {
            if let title = try? await client.getTrack(id: trackId).album?.title {
                albumTitles[albumId] = title
            } else {
                albumLookups.remove(albumId)
            }
        }
    }

    /// A tapped search result: select the track and fly the camera to it. Nothing plays.
    func selectSearchResult(_ id: String) {
        selectedTrackId = id
        flyToId = id
        flyTrigger += 1
        searchListHidden = true
    }

    // MARK: Taps

    /// Runs the action the router picks for a tap (`nil` id = empty space).
    func handleTap(_ id: String?) {
        switch VibeTapRouter.action(for: id, state: .init(pickingPath: panel == .songPath && songPath.nextSlot != nil)) {
        case .pickPathTrack(let tid): pickPathTrack(tid)
        case .select(let tid): selectedTrackId = tid
        case .deselect:
            selectedTrackId = nil
            similarIds = []
        case .ignore: break
        }
    }

    // MARK: Track menu actions

    /// "show similar": lights the track and its 50 nearest matches; the queue is untouched.
    func showSimilar(trackId: String, client: KimaAPIClient) async {
        do {
            let result = try await client.getVibeSimilarTracksWithSimilarity(trackId: trackId, limit: 50)
            similarIds = [trackId] + result.tracks.map(\.id)
            legendPinned = nil
        } catch {
            report(VibeErrorCopy.similar(error))
        }
    }
}
