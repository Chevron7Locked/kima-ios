import Foundation

#if DEBUG
extension VibeMapViewModel {
    /// Applies the map-state launch args used for screenshots (`-kima-vibe-*`, read from UserDefaults,
    /// which holds launch arguments): search, select, pin, path-from, path-to, blend-more, blend-less,
    /// similar, panel, rail, stepback.
    func applyDebugLaunchState() {
        let d = UserDefaults.standard
        if let q = d.string(forKey: "kima-vibe-search") { searchQuery = q; updateSearch() }
        // Each index flag below is the nth track on the map.
        if d.object(forKey: "kima-vibe-select") != nil, case .loaded(let tracks) = phase {
            let n = d.integer(forKey: "kima-vibe-select")
            if tracks.indices.contains(n) { selectedTrackId = tracks[n].id }
        }
        if let mood = d.string(forKey: "kima-vibe-pin"), tracksByMood[mood] != nil { toggleLegend(mood) }
        // Opens the song path with that track as its start.
        if d.object(forKey: "kima-vibe-path-from") != nil, case .loaded(let tracks) = phase {
            let n = d.integer(forKey: "kima-vibe-path-from")
            if tracks.indices.contains(n) { beginSongPath(from: tracks[n].id) }
        }
        // Sets that track as the song path's end.
        if d.object(forKey: "kima-vibe-path-to") != nil, case .loaded(let tracks) = phase {
            let n = d.integer(forKey: "kima-vibe-path-to")
            if tracks.indices.contains(n) { pickPathTrack(tracks[n].id) }
        }
        // Adds that track to the blend's "more like" or "less like" column (opens the blend).
        if d.object(forKey: "kima-vibe-blend-more") != nil, case .loaded(let tracks) = phase {
            let n = d.integer(forKey: "kima-vibe-blend-more")
            if tracks.indices.contains(n) { addToBlend(tracks[n].id, column: .more) }
        }
        if d.object(forKey: "kima-vibe-blend-less") != nil, case .loaded(let tracks) = phase {
            let n = d.integer(forKey: "kima-vibe-blend-less")
            if tracks.indices.contains(n) { addToBlend(tracks[n].id, column: .less) }
        }
        // Lights that track and the 30 after it, as "show similar" does.
        if d.object(forKey: "kima-vibe-similar") != nil, case .loaded(let tracks) = phase {
            let n = d.integer(forKey: "kima-vibe-similar")
            if tracks.indices.contains(n) { similarIds = tracks[n...].prefix(31).map(\.id) }
        }
        switch d.string(forKey: "kima-vibe-panel") {
        case "songpath": panel = .songPath
        case "blend": panel = .blend
        default: break
        }
        // The rail tool starts from the selected star.
        switch d.string(forKey: "kima-vibe-rail") {
        case "songpath": toggleTool(.songPath)
        case "blend": toggleTool(.blend)
        default: break
        }
        // Taps "clear" n times, after everything above.
        for _ in 0..<d.integer(forKey: "kima-vibe-stepback") { stepBack() }
    }
}
#endif
