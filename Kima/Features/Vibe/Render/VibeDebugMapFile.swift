import Foundation

/// DEBUG launch arguments for repeatable map screenshots (`-kima-vibe-*`). Every flag is false or nil in a release build.
enum VibeDebugFlags {
    #if DEBUG
    private static let args = CommandLine.arguments
    private static func value(after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    /// Loads `Documents/<name>` (a saved `/api/vibe/map` body) instead of the network.
    static let mapFile = value(after: "-kima-vibe-map-file")
    /// Time 0, reveal finished, steady ring opacity: repeatable frames.
    static let still = args.contains("-kima-vibe-still")
    /// Hides every SwiftUI layer over the map.
    static let bare = args.contains("-kima-vibe-bare")
    /// Comma list of `sky,stars,rings`; default all (`glow` is accepted and ignored).
    static let layers: Set<String>? = value(after: "-kima-vibe-layers").map { Set($0.split(separator: ",").map(String.init)) }
    /// Treats `tracks[i]` as the playing track (no audio).
    static let fakePlayingIndex: Int? = value(after: "-kima-vibe-fake-playing").flatMap(Int.init)
    /// Half a second after the first frame, runs "find playing track".
    static let locate = args.contains("-kima-vibe-locate")
    /// Once the map is measured, puts the camera at the home direction and maximum distance.
    static let zoomOut = args.contains("-kima-vibe-zoom-out")
    /// Pins the camera at this fraction of the home distance (screenshots of zoomed-in stars; applied every frame).
    static let zoomFactor: Float? = value(after: "-kima-vibe-zoom").flatMap { Float($0) }
    /// Turns the camera steadily, for screen recordings.
    static let orbitDemo = args.contains("-kima-vibe-orbit-demo")
    /// Gives every synthetic track a title too long for one line of the readout.
    static let longTitle = args.contains("-kima-vibe-long-title")
    /// Tints the stars of one mood, as a pinned mood chip does (happy, sad, relaxed, aggressive, party).
    static let focusMood = value(after: "-kima-vibe-focus-mood")
    /// Ring colour for what built the queue (songPath, playSimilar, similar, blend); rings the playing star if no source.
    static let operation: VibeOperationKind? = value(after: "-kima-vibe-operation").flatMap(VibeOperationKind.init)
    /// Pretends the Metal renderer couldn't start, to show the map's error card.
    static let metalFail = args.contains("-kima-vibe-metal-fail")
    #else
    static let mapFile: String? = nil
    static let still = false
    static let bare = false
    static let layers: Set<String>? = nil
    static let fakePlayingIndex: Int? = nil
    static let locate = false
    static let zoomOut = false
    static let zoomFactor: Float? = nil
    static let orbitDemo = false
    static let longTitle = false
    static let focusMood: String? = nil
    static let operation: VibeOperationKind? = nil
    static let metalFail = false
    #endif

    /// Whether a layer (`sky`, `stars` or `rings`) is drawn.
    static func layerOn(_ name: String) -> Bool { layers?.contains(name) ?? true }
}

#if DEBUG
enum VibeDebugMapFile {
    /// The map saved in `Documents/<name>` when `-kima-vibe-map-file <name>` is given.
    static func responseIfRequested() -> VibeMapResponse? {
        guard let name = VibeDebugFlags.mapFile,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? Data(contentsOf: docs.appendingPathComponent(name)) else {
            if let name = VibeDebugFlags.mapFile { NSLog("vibe-map file %@ could not be read", name) }
            return nil
        }
        do {
            let map = try JSONDecoder().decode(VibeMapResponse.self, from: data)
            NSLog("vibe-map file %@ loaded, %d tracks", name, map.tracks.count)
            return map
        } catch {
            NSLog("vibe-map file %@ did not decode: %@", name, String(describing: error))
            return nil
        }
    }
}
#endif
