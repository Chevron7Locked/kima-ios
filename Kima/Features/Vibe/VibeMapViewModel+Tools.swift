import Foundation

/// What one tap on the rail's back button undoes: the most recent thing that is still on screen.
enum VibeStepBack: Equatable {
    case closePanel, clearSearch, clearSimilar, unpinMood, deselect

    /// The words under the back button: what the next tap does.
    var railLabel: String {
        switch self {
        case .closePanel: return "close"
        case .clearSearch: return "clear search"
        case .clearSimilar: return "clear similar"
        case .unpinMood: return "unpin"
        case .deselect: return "deselect"
        }
    }
}

extension VibeMapViewModel {

    // MARK: Back

    /// What the back button undoes next: the newest thing in `stepOrder` that can be seen now; nil
    /// when there is nothing (the button hides).
    var nextStepBack: VibeStepBack? { stepOrder.last(where: isShowing) }

    /// Whether a step's thing is on screen, so the back button never undoes something hidden.
    func isShowing(_ step: VibeStepBack) -> Bool {
        switch step {
        case .closePanel: return panel != nil
        case .clearSearch: return !searchQuery.isEmpty
        // Search matches and a blend's result light the map instead of a similar result.
        case .clearSimilar: return !similarIds.isEmpty && searchMatches.ids.isEmpty && blendResults.isEmpty
        // The chip hides under the search list and while a star is selected.
        case .unpinMood: return legendPinned != nil && !searchListShown && selectedTrackId == nil
        case .deselect: return selectedTrackId != nil
        }
    }

    /// What VoiceOver says for the back button: the whole phrase, naming the panel, mood or track.
    var stepBackSpokenLabel: String? {
        switch nextStepBack {
        case .closePanel: return "close \(panel?.title ?? "panel")"
        case .unpinMood: return "unpin \(legendPinned.map(VibeMoodPalette.label(for:)) ?? "mood")"
        case .deselect: return "deselect \(selectedTrackId.flatMap(trackFor(id:))?.title.lowercased() ?? "track")"
        case let step?: return step.railLabel
        case nil: return nil
        }
    }

    /// Undoes one thing, the one `nextStepBack` names.
    func stepBack() {
        switch nextStepBack {
        case .closePanel:
            panel = nil
            modeError = nil
        case .clearSearch: clearSearch()
        case .clearSimilar: similarIds = []
        case .unpinMood: legendPinned = nil
        case .deselect: selectedTrackId = nil
        case nil: break
        }
    }

    /// The search list is showing: there is a summary to show and no pick has hidden it.
    var searchListShown: Bool {
        !searchListHidden && VibeLibrarySearch.summary(searchMatches) != nil
    }

    // MARK: Rail tools

    /// The rail's "song path" or "blend". Closes the tool if it is open. Otherwise opens it, starting
    /// from the selected star when there is one: it becomes the song path's start, or joins "more like".
    func toggleTool(_ tool: VibePanel) {
        modeError = nil
        if panel == tool {
            panel = nil
            return
        }
        guard let seed = selectedTrackId else {
            panel = tool
            return
        }
        switch tool {
        case .songPath: beginSongPath(from: seed)
        case .blend: addToBlend(seed, column: .more)
        }
    }
}
